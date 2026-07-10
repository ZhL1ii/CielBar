import Foundation

final class AerospaceEventMonitor {
    typealias ChangeHandler = (SpacesChangeReason) -> Void

    private static let subscribedEvents = [
        "focus-changed",
        "focused-workspace-changed",
        "focused-monitor-changed",
        "window-detected",
    ]
    private static let subscribedEventNames = Set(subscribedEvents)

    private let executablePath: String
    private let stateQueue = DispatchQueue(
        label: "moe.ciel.CielBar.aerospace-event-monitor")
    private let stateQueueKey = DispatchSpecificKey<Void>()
    private let maximumRetryDelay: TimeInterval = 30

    private var process: Process?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var retryWorkItem: DispatchWorkItem?
    private var retryRequestID = 0
    private var retryAttempt = 0
    private var onChange: ChangeHandler?
    private var isMonitoring = false
    private var isStoppingProcess = false

    init(executablePath: String) {
        self.executablePath = executablePath
        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    func startMonitoring(onChange: @escaping ChangeHandler) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.onChange = onChange
            guard !self.isMonitoring else { return }

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

    private func startProcessLocked() {
        guard isMonitoring, process == nil, retryWorkItem == nil else {
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["subscribe", "--no-send-initial"]
            + Self.subscribedEvents
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
        isStoppingProcess = false

        do {
            try process.run()
        } catch {
            print("AeroSpace event monitor launch error: \(error)")
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
        guard !line.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: line),
            let payload = object as? [String: Any],
            let event = payload["_event"] as? String,
            Self.subscribedEventNames.contains(event)
        else {
            return
        }

        retryAttempt = 0
        onChange?(.providerEvent)
    }

    private func handleTerminationLocked(_ process: Process) {
        guard self.process === process else { return }

        let wasStoppingProcess = isStoppingProcess
        let terminationReason = process.terminationReason
        let terminationStatus = process.terminationStatus
        cleanUpProcessLocked(process)

        guard isMonitoring else { return }
        if wasStoppingProcess {
            startProcessLocked()
        } else if terminationReason == .uncaughtSignal {
            print(
                "AeroSpace event monitor terminated by signal "
                    + "\(terminationStatus); retrying")
            scheduleRetryLocked()
        } else if terminationStatus != 0 {
            print(
                "AeroSpace event monitor exited with status "
                    + "\(terminationStatus); using fallback polling")
        }
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
            guard let self, self.retryRequestID == requestID else { return }
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

        guard let process else {
            outputHandle = nil
            return
        }

        isStoppingProcess = true
        if process.isRunning {
            process.terminate()
        } else {
            cleanUpProcessLocked(process)
        }
    }

    private func cleanUpProcessLocked(_ process: Process) {
        guard self.process === process else { return }

        outputHandle?.readabilityHandler = nil
        try? outputHandle?.close()
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: false)
        process.terminationHandler = nil
        self.process = nil
        isStoppingProcess = false
    }
}
