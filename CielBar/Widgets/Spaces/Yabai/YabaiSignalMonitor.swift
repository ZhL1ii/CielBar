import Darwin
import Foundation

final class YabaiSignalMonitor {
    typealias ChangeHandler = (SpacesProviderChange) -> Void

    private struct RegisteredSignal: Decodable {
        let label: String?
        let event: String?
        let action: String?
    }

    static let focusEvents = [
        "space_changed",
        "window_focused",
    ]
    static let otherMonitoredEvents = [
        "space_created",
        "space_destroyed",
        "window_created",
        "window_destroyed",
        "window_title_changed",
        "window_minimized",
        "window_deminimized",
        "display_changed",
        "display_added",
        "display_removed",
        "system_woke",
    ]
    private static let monitoredEvents = focusEvents + otherMonitoredEvents
    private static let labelPrefix = "CielBar.spaces-event."

    private let executablePath: String
    private let processIdentifier = ProcessInfo.processInfo.processIdentifier
    private let stateQueue = DispatchQueue(
        label: "moe.ciel.CielBar.yabai-signal-monitor")
    private let stateQueueKey = DispatchSpecificKey<Void>()

    private var genericSignalSource: DispatchSourceSignal?
    private var focusSignalSource: DispatchSourceSignal?
    private var registeredLabels = Set<String>()
    private var onChange: ChangeHandler?
    private var isMonitoring = false
    private var connectionState: SpacesConnectionState?
    private var hasReportedFailure = false
    private var retryWorkItem: DispatchWorkItem?
    private var retryRequestID = 0
    private var retryAttempt = 0

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
            self.installSignalSourceLocked()
            self.reconcileSignalsLocked()
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

    private func installSignalSourceLocked() {
        if genericSignalSource == nil {
            genericSignalSource = makeSignalSourceLocked(signal: SIGUSR1)
        }
        if focusSignalSource == nil {
            focusSignalSource = makeSignalSourceLocked(signal: SIGUSR2)
        }
    }

    private func makeSignalSourceLocked(
        signal: Int32
    ) -> DispatchSourceSignal {
        _ = Darwin.signal(signal, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
            signal: signal, queue: stateQueue)
        source.setEventHandler { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.onChange?(Self.providerChange(for: signal))
        }
        source.resume()
        return source
    }

    static func providerChange(for signal: Int32) -> SpacesProviderChange {
        switch signal {
        case SIGUSR1:
            return SpacesProviderChange(reason: .providerEvent)
        case SIGUSR2:
            return SpacesProviderChange(
                reason: .providerFocusEvent,
                refreshPolicy: .immediate)
        default:
            preconditionFailure("Unexpected yabai signal: \(signal)")
        }
    }

    static func action(for event: String, processIdentifier: Int32) -> String {
        let signalName = focusEvents.contains(event) ? "USR2" : "USR1"
        return "/bin/kill -\(signalName) \(processIdentifier)"
    }

    func checkConnection() {
        stateQueue.async { [weak self] in
            guard let self, self.isMonitoring, self.retryWorkItem == nil else { return }
            self.reconcileSignalsLocked()
        }
    }

    private func reconcileSignalsLocked() {
        guard isMonitoring else { return }
        guard let data = runYabaiCommand(arguments: ["-m", "signal", "--list"]),
            let signals = try? JSONDecoder().decode([RegisteredSignal].self, from: data)
        else {
            scheduleRetryLocked()
            return
        }

        // Remove registrations left by exited CielBar instances, never another live instance.
        let ownPrefix = Self.labelPrefix + "\(processIdentifier)."
        for label in signals.compactMap(\.label)
        where label.hasPrefix(Self.labelPrefix) && !label.hasPrefix(ownPrefix) {
            let suffix = label.dropFirst(Self.labelPrefix.count)
            if let pidText = suffix.split(separator: ".").first,
                let pid = Int32(pidText), pid > 0,
                Darwin.kill(pid, 0) == -1 && errno == ESRCH
            {
                _ = removeSignalLocked(label: label)
            }
        }

        let missingEvents = Self.monitoredEvents.filter { event in
            !signals.contains {
                $0.label == ownPrefix + event && $0.event == event
                    && $0.action == Self.action(for: event, processIdentifier: processIdentifier)
            }
        }
        if !missingEvents.isEmpty { setConnectionStateLocked(.reconnecting) }
        for event in missingEvents {
            let label = ownPrefix + event
            // A labelled add replaces an existing registration with the same label.
            guard runYabaiCommand(arguments: [
                "-m", "signal", "--add", "event=\(event)",
                "action=\(Self.action(for: event, processIdentifier: processIdentifier))",
                "label=\(label)",
            ]) != nil else {
                scheduleRetryLocked()
                return
            }
            registeredLabels.insert(label)
        }
        registeredLabels = Set(Self.monitoredEvents.map { ownPrefix + $0 })
        retryAttempt = 0
        setConnectionStateLocked(.connected)
    }

    private func setConnectionStateLocked(_ state: SpacesConnectionState, reason: String? = nil) {
        if state == .connected { hasReportedFailure = false }
        if let reason, !hasReportedFailure {
            print("Yabai event connection failed: \(reason)")
            hasReportedFailure = true
        }
        guard connectionState != state else { return }
        connectionState = state
        print("Yabai events: \(state)")
        onChange?(SpacesProviderChange(
            reason: .providerConnection, refreshPolicy: .immediate, connectionState: state))
    }

    private func scheduleRetryLocked() {
        setConnectionStateLocked(.reconnecting)
        guard isMonitoring, retryWorkItem == nil else { return }
        let delay = min(pow(2, Double(retryAttempt)), 10)
        retryAttempt = min(retryAttempt + 1, 4)
        retryRequestID += 1
        let requestID = retryRequestID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isMonitoring, self.retryRequestID == requestID else { return }
            self.retryWorkItem = nil
            self.reconcileSignalsLocked()
        }
        retryWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func stopMonitoringLocked() {
        guard isMonitoring || genericSignalSource != nil || focusSignalSource != nil
            || !registeredLabels.isEmpty
        else {
            onChange = nil
            return
        }

        isMonitoring = false
        onChange = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryRequestID += 1
        retryAttempt = 0
        connectionState = nil
        hasReportedFailure = false
        genericSignalSource?.cancel()
        genericSignalSource = nil
        focusSignalSource?.cancel()
        focusSignalSource = nil

        // A missing label is harmless: clean only registrations that still exist remotely.
        if let data = runYabaiCommand(arguments: ["-m", "signal", "--list"]),
            let signals = try? JSONDecoder().decode([RegisteredSignal].self, from: data)
        {
            for label in signals.compactMap(\.label) where registeredLabels.contains(label) {
                _ = removeSignalLocked(label: label)
            }
        }
        registeredLabels.removeAll(keepingCapacity: false)
    }

    private func removeSignalLocked(label: String) -> Bool {
        guard
            runYabaiCommand(arguments: [
                "-m", "signal", "--remove", label,
            ]) != nil
        else {
            print("Yabai signal monitor could not remove label \(label)")
            return false
        }
        return true
    }

    private func runYabaiCommand(arguments: [String]) -> Data? {
        do {
            return try SpacesCommand.run(executablePath: executablePath, arguments: arguments)
        } catch {
            if isMonitoring {
                setConnectionStateLocked(.reconnecting, reason: error.localizedDescription)
            }
            return nil
        }
    }
}
