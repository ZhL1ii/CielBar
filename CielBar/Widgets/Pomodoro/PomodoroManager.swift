import AppKit
import Combine
import Foundation

enum PomodoroPhase: Equatable {
    case work
    case `break`

    /// Work and break alternate, so this property returns the other phase.
    var next: PomodoroPhase {
        switch self {
        case .work:
            return .break
        case .break:
            return .work
        }
    }
}

struct PomodoroConfiguration: Equatable {
    static let defaultWorkDurationMinutes = 45
    static let defaultBreakDurationMinutes = 10
    static let validDurationRange = 1 ... 1440

    static let defaultValue = PomodoroConfiguration(
        workDurationMinutes: defaultWorkDurationMinutes,
        breakDurationMinutes: defaultBreakDurationMinutes
    )

    let workDurationMinutes: Int
    let breakDurationMinutes: Int

    init(
        workDurationMinutes: Int? = nil,
        breakDurationMinutes: Int? = nil
    ) {
        self.workDurationMinutes = Self.validatedDuration(
            workDurationMinutes,
            fallback: Self.defaultWorkDurationMinutes
        )
        self.breakDurationMinutes = Self.validatedDuration(
            breakDurationMinutes,
            fallback: Self.defaultBreakDurationMinutes
        )
    }

    init(config: ConfigData) {
        // `intValue` is nil when a key is missing or has another TOML type.
        // Validate the fields separately so one invalid phase does not affect
        // the other.
        self.init(
            workDurationMinutes: config["work-duration"]?.intValue,
            breakDurationMinutes: config["break-duration"]?.intValue
        )
    }

    var workDurationSeconds: Int {
        workDurationMinutes * 60
    }

    var breakDurationSeconds: Int {
        breakDurationMinutes * 60
    }

    func durationSeconds(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .work:
            return workDurationSeconds
        case .break:
            return breakDurationSeconds
        }
    }

    private static func validatedDuration(
        _ value: Int?,
        fallback: Int
    ) -> Int {
        // A zero-length phase would end immediately. Use the field's default
        // for values outside the allowed range.
        guard let value, validDurationRange.contains(value) else {
            return fallback
        }
        return value
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    // Published state is main-actor isolated. Timer and control callbacks
    // update it on that actor before SwiftUI observes the changes.
    @Published private(set) var phase: PomodoroPhase
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning: Bool

    private(set) var configuration: PomodoroConfiguration
    private(set) var deadline: Date?

    private let notificationCenter: NotificationCenter
    // Tests supply a mutable clock so they can advance time without waiting.
    private let now: () -> Date
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var isSleeping = false
    private var wasRunningBeforeSleep = false

    init(
        configuration: PomodoroConfiguration = .defaultValue,
        now: @escaping () -> Date = { Date() },
        notificationCenter: NotificationCenter = NSWorkspace.shared
            .notificationCenter
    ) {
        self.configuration = configuration
        self.now = now
        self.notificationCenter = notificationCenter
        // Start each manager with a paused work phase.
        phase = .work
        remainingSeconds = configuration.workDurationSeconds
        isRunning = false
        deadline = nil
        startMonitoring()
    }

    convenience init(
        config: ConfigData,
        now: @escaping () -> Date = { Date() },
        notificationCenter: NotificationCenter = NSWorkspace.shared
            .notificationCenter
    ) {
        self.init(
            configuration: PomodoroConfiguration(config: config),
            now: now,
            notificationCenter: notificationCenter)
    }

    func updateConfiguration(_ configuration: PomodoroConfiguration) {
        // A reload changes only durations used by later resets or phase
        // changes. Keep the live countdown unchanged.
        self.configuration = configuration
    }

    deinit {
        // A deinitializer is not main-actor isolated, so release these
        // resources directly here.
        timer?.invalidate()
        if let sleepObserver {
            notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
        }
    }

    var formattedRemainingTime: String {
        Self.formattedTime(for: remainingSeconds)
    }

    static func formattedTime(for seconds: Int) -> String {
        // Clamp negatives to zero. Hours use at least two digits but can exceed
        // 99, which lets the maximum duration display as 24:00:00.
        let totalSeconds = max(0, seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        func padded(_ value: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, 2 - text.count))
                + text
        }

        return "\(padded(hours)):\(padded(minutes)):\(padded(remainingSeconds))"
    }

    func play() {
        play(at: now())
    }

    func play(at date: Date) {
        guard !isRunning, !isSleeping else { return }

        if remainingSeconds <= 0 {
            // Expiry normally moves to the next phase before zero is visible.
            // This also repairs a zero remainder if another path produces one.
            remainingSeconds = configuration.durationSeconds(for: phase)
        }

        // Keep an absolute deadline instead of decrementing the remainder on
        // each callback. Delayed callbacks then do not accumulate drift, and
        // resume starts from the saved remainder.
        deadline = date.addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        startTimer()
    }

    func pause() {
        pause(at: now())
    }

    func pause(at date: Date) {
        guard isRunning else { return }

        if isSleeping {
            // The controls are normally unavailable during sleep, but a pause
            // must cancel any resume that the wake handler would otherwise do.
            deadline = nil
            isRunning = false
            wasRunningBeforeSleep = false
            stopTimer()
            return
        }

        // Settle the remainder before clearing the deadline. If the phase
        // expired, tick performs the normal single transition and never leaves
        // zero visible.
        tick(at: date)
        deadline = nil
        isRunning = false
        wasRunningBeforeSleep = false
        stopTimer()
    }

    func reset() {
        // Keep the phase, restore its configured duration, and pause.
        isRunning = false
        deadline = nil
        remainingSeconds = configuration.durationSeconds(for: phase)
        wasRunningBeforeSleep = false
        stopTimer()
    }

    func previousPhase() {
        // There are only two phases, so both navigation controls select the
        // other one. Manual navigation discards the current progress.
        switchToOtherPhase()
    }

    func nextPhase() {
        switchToOtherPhase()
    }

    func tick() {
        tick(at: now())
    }

    func tick(at date: Date) {
        guard isRunning, !isSleeping, let deadline else { return }

        // Do not publish zero. A delayed callback changes phase when it runs,
        // and the new phase starts from that time.
        if date >= deadline {
            phase = phase.next
            remainingSeconds = configuration.durationSeconds(for: phase)
            self.deadline = date.addingTimeInterval(
                TimeInterval(remainingSeconds)
            )
            return
        }

        // Round up fractional seconds so a play callback does not immediately
        // lose a second. Cap the result so a clock moving backward cannot add
        // time.
        let seconds = Int(ceil(deadline.timeIntervalSince(date)))
        remainingSeconds = min(
            max(0, seconds),
            configuration.durationSeconds(for: phase)
        )
    }

    private func switchToOtherPhase() {
        // Manual navigation starts the other phase from its full duration and
        // pauses. There is no phase history to restore.
        phase = phase.next
        remainingSeconds = configuration.durationSeconds(for: phase)
        isRunning = false
        deadline = nil
        wasRunningBeforeSleep = false
        stopTimer()
    }

    private func startMonitoring() {
        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleSystemWillSleep(at: self.now())
            }
        }

        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleSystemDidWake(at: self.now())
            }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        self.timer = timer
        // Common modes keep the countdown active while the menu bar is tracking
        // input. The callback still runs on the main run loop.
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func handleSystemWillSleep(at date: Date) {
        guard !isSleeping else { return }

        isSleeping = true
        wasRunningBeforeSleep = isRunning
        stopTimer()

        // Keep the absolute deadline. While the phase is active, refresh the
        // cached value without allowing sleep to switch phases.
        if isRunning, let deadline, date < deadline {
            updateRemainingSeconds(at: date, deadline: deadline)
        }
    }

    func handleSystemDidWake(at date: Date) {
        guard isSleeping else { return }

        isSleeping = false
        let shouldResume = wasRunningBeforeSleep
        wasRunningBeforeSleep = false

        guard shouldResume, isRunning, let deadline else { return }

        if date >= deadline {
            // Even if sleep spans several phase lengths, recovery makes one
            // transition and pauses on the new phase's full duration.
            phase = phase.next
            remainingSeconds = configuration.durationSeconds(for: phase)
            self.deadline = nil
            isRunning = false
            stopTimer()
            return
        }

        // The original deadline includes all elapsed sleep time, so the resumed
        // timer does not drift.
        updateRemainingSeconds(at: date, deadline: deadline)
        startTimer()
    }

    private func updateRemainingSeconds(at date: Date, deadline: Date) {
        let seconds = Int(ceil(deadline.timeIntervalSince(date)))
        remainingSeconds = min(
            max(0, seconds),
            configuration.durationSeconds(for: phase)
        )
    }
}
