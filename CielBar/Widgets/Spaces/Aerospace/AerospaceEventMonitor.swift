import Darwin
import Foundation

enum AerospaceEventJSONLParser {
    private struct Payload: Decodable {
        let event: String
        let workspace: String?
        let windowID: Int?

        enum CodingKeys: String, CodingKey {
            case event = "_event"
            case workspace
            case windowID = "windowId"
        }
    }

    struct Event {
        let name: String
        let workspace: String?
        let windowID: Int?

        var focusChange: SpacesFocusChange? {
            guard let workspace else { return nil }
            switch name {
            case "focus-changed":
                return SpacesFocusChange(
                    workspaceID: workspace,
                    windowID: windowID,
                    updatesWindowFocus: true)
            case "focused-workspace-changed":
                return SpacesFocusChange(
                    workspaceID: workspace,
                    windowID: nil,
                    updatesWindowFocus: false)
            default:
                return nil
            }
        }
    }

    static let relevantEvents = [
        "focus-changed",
        "focused-workspace-changed",
        "focused-monitor-changed",
        "window-detected",
    ]
    private static let relevantEventNames = Set(relevantEvents)

    static func isRelevantEvent(_ line: Data) -> Bool {
        parseRelevantEvent(line) != nil
    }

    static func parseRelevantEvent(_ line: Data) -> Event? {
        guard
            let payload = try? JSONDecoder().decode(Payload.self, from: line),
            relevantEventNames.contains(payload.event)
        else {
            return nil
        }
        return Event(
            name: payload.event,
            workspace: payload.workspace,
            windowID: payload.windowID)
    }
}

final class AerospaceEventMonitor {
    typealias ChangeHandler = (SpacesProviderChange) -> Void

    private static let subscribedEvents =
        AerospaceEventJSONLParser.relevantEvents

    private let executablePath: String
    private let stateQueue = DispatchQueue(
        label: "moe.ciel.CielBar.aerospace-event-monitor")
    private let stateQueueKey = DispatchSpecificKey<Void>()
    private let maximumRetryDelay: TimeInterval = 10

    private var process: Process?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var retryWorkItem: DispatchWorkItem?
    private var retryRequestID = 0
    private var retryAttempt = 0
    private var onChange: ChangeHandler?
    private var isMonitoring = false
    private var connectionState: SpacesConnectionState?
    private var hasReportedFailure = false
    private var connectionTimeout: DispatchWorkItem?

    init(executablePath: String) {
        self.executablePath = executablePath
        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    func startMonitoring(onChange: @escaping ChangeHandler) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.onChange = onChange
            guard !self.isMonitoring else {
                self.startProcessLocked()
                return
            }

            self.isMonitoring = true
            self.startProcessLocked()
        }
    }

    func stopMonitoring() {
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            stopMonitoringLocked()
        } else {
            stateQueue.sync { [weak self] in
                self?.stopMonitoringLocked()
            }
        }
    }

    func checkConnection() {
        stateQueue.async { [weak self] in
            self?.startProcessLocked()
        }
    }

    private func setConnectionStateLocked(_ state: SpacesConnectionState, reason: String? = nil) {
        if state == .connected { hasReportedFailure = false }
        if let reason, !hasReportedFailure {
            print("AeroSpace event connection failed: \(reason)")
            hasReportedFailure = true
        }
        guard connectionState != state else { return }
        connectionState = state
        print("AeroSpace events: \(state)")
        onChange?(SpacesProviderChange(
            reason: .providerConnection, refreshPolicy: .immediate, connectionState: state))
    }

    private func startProcessLocked() {
        guard isMonitoring, process == nil, retryWorkItem == nil else {
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["subscribe"]
            + Self.subscribedEvents
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        outputHandle.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty, let process else { return }
            self?.stateQueue.async { [weak self, weak process] in
                guard let self, let process else { return }
                self.consumeOutputLocked(data, from: process)
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.stateQueue.async { [weak self, weak process] in
                guard let self, let process else { return }
                self.handleTerminationLocked(process)
            }
        }

        self.process = process
        self.outputHandle = outputHandle
        outputBuffer.removeAll(keepingCapacity: true)
        do {
            try process.run()
            let timeout = DispatchWorkItem { [weak self, weak process] in
                guard let self, let process, self.process === process,
                    self.connectionState != .connected, process.isRunning
                else { return }
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            connectionTimeout = timeout
            stateQueue.asyncAfter(deadline: .now() + 3, execute: timeout)
        } catch {
            setConnectionStateLocked(.reconnecting, reason: error.localizedDescription)
            cleanUpProcessLocked(process)
            scheduleRetryLocked()
        }
    }

    private func consumeOutputLocked(_ data: Data, from process: Process) {
        guard isMonitoring, self.process === process else { return }

        outputBuffer.append(data)
        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newlineIndex])
            outputBuffer.removeSubrange(
                outputBuffer.startIndex...newlineIndex)
            handleLineLocked(line)
        }
    }

    private func handleLineLocked(_ line: Data) {
        guard
            let event = AerospaceEventJSONLParser.parseRelevantEvent(line)
        else {
            return
        }

        connectionTimeout?.cancel()
        connectionTimeout = nil
        retryAttempt = 0
        setConnectionStateLocked(.connected)
        onChange?(
            SpacesProviderChange(
                reason: .providerEvent,
                focusChange: event.focusChange))
    }

    private func handleTerminationLocked(_ process: Process) {
        guard self.process === process else { return }

        let reason = process.terminationReason == .exit
            ? "Subscription exited with status \(process.terminationStatus)"
            : "Subscription terminated by signal \(process.terminationStatus)"
        cleanUpProcessLocked(process)
        guard isMonitoring else { return }
        setConnectionStateLocked(.reconnecting, reason: reason)
        scheduleRetryLocked()
    }

    private func scheduleRetryLocked() {
        guard isMonitoring, process == nil, retryWorkItem == nil else {
            return
        }

        let delay = min(
            pow(2, Double(retryAttempt)), maximumRetryDelay)
        retryAttempt = min(retryAttempt + 1, 5)
        retryRequestID += 1
        let requestID = retryRequestID

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMonitoring, self.retryRequestID == requestID else { return }
            self.retryWorkItem = nil
            self.startProcessLocked()
        }
        retryWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func stopMonitoringLocked() {
        isMonitoring = false
        onChange = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryRequestID += 1
        retryAttempt = 0
        outputBuffer.removeAll(keepingCapacity: false)
        outputHandle?.readabilityHandler = nil

        connectionState = nil
        hasReportedFailure = false
        guard let process else { return }
        cleanUpProcessLocked(process)
        if process.isRunning {
            process.terminate()
            // The CLI is our child; ensure shutdown does not leave an orphan subscription.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    private func cleanUpProcessLocked(_ process: Process) {
        guard self.process === process else { return }

        connectionTimeout?.cancel()
        connectionTimeout = nil
        outputHandle?.readabilityHandler = nil
        try? outputHandle?.close()
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        process.terminationHandler = nil
        self.process = nil
    }
}
