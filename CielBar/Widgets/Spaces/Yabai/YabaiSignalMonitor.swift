import Darwin
import Foundation

final class YabaiSignalMonitor {
    typealias ChangeHandler = (SpacesProviderChange) -> Void

    private struct RegisteredSignal: Decodable {
        let label: String?
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
            self.removeStaleSignalsLocked()
            self.registerSignalsLocked()
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

    private func removeStaleSignalsLocked() {
        guard
            let data = runYabaiCommand(
                arguments: ["-m", "signal", "--list"],
                captureOutput: true)
        else {
            print(
                "Yabai signal monitor could not list stale signals; "
                    + "using fallback polling")
            return
        }

        let signals: [RegisteredSignal]
        do {
            signals = try JSONDecoder().decode(
                [RegisteredSignal].self, from: data)
        } catch {
            print("Decode yabai signals error: \(error)")
            return
        }

        for label in signals.compactMap(\.label)
        where label.hasPrefix(Self.labelPrefix) {
            _ = removeSignalLocked(label: label)
        }
    }

    private func registerSignalsLocked() {
        for event in Self.monitoredEvents {
            let label = Self.labelPrefix
                + "\(processIdentifier).\(event)"
            let action = Self.action(
                for: event, processIdentifier: processIdentifier)
            let wasAdded = runYabaiCommand(arguments: [
                "-m", "signal", "--add",
                "event=\(event)",
                "action=\(action)",
                "label=\(label)",
            ]) != nil

            if wasAdded {
                registeredLabels.insert(label)
            } else {
                print(
                    "Yabai signal monitor could not register \(event); "
                        + "using fallback polling")
            }
        }
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
        genericSignalSource?.cancel()
        genericSignalSource = nil
        focusSignalSource?.cancel()
        focusSignalSource = nil

        for label in registeredLabels {
            _ = removeSignalLocked(label: label)
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

    private func runYabaiCommand(
        arguments: [String], captureOutput: Bool = false
    ) -> Data? {
        let process = Process()
        let outputPipe = captureOutput ? Pipe() : nil
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("Yabai signal monitor launch error: \(error)")
            return nil
        }

        let data = outputPipe?.fileHandleForReading.readDataToEndOfFile()
            ?? Data()
        process.waitUntilExit()
        guard process.terminationReason == .exit,
            process.terminationStatus == 0
        else {
            print(
                "Yabai signal command exited with status "
                    + "\(process.terminationStatus)")
            return nil
        }
        return data
    }
}
