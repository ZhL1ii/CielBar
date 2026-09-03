import Combine
import Foundation

enum PomodoroPhase: Equatable {
    case work
    case `break`

    /// Work and break alternate, so every transition selects the other phase.
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
        // `intValue` returns nil for a missing key or a TOML value of another
        // type. Validate each field independently so one bad value does not
        // discard a valid value from the other phase.
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
        // Zero would make the phase end immediately. Keep only values in the
        // documented range and use the field's fallback for everything else.
        guard let value, validDurationRange.contains(value) else {
            return fallback
        }
        return value
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    // This is UI state. Main-actor isolation keeps published changes on the
    // main actor when the timer or controls update the manager.
    @Published private(set) var phase: PomodoroPhase
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning: Bool

    private(set) var configuration: PomodoroConfiguration
    private(set) var deadline: Date?

    // Tests inject a clock here so they can advance time without waiting.
    private let now: () -> Date

    init(
        configuration: PomodoroConfiguration = .defaultValue,
        now: @escaping () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.now = now
        // A new manager starts a fresh work phase in the paused state.
        phase = .work
        remainingSeconds = configuration.workDurationSeconds
        isRunning = false
        deadline = nil
    }

    convenience init(
        config: ConfigData,
        now: @escaping () -> Date = { Date() }
    ) {
        self.init(configuration: PomodoroConfiguration(config: config), now: now)
    }

    var formattedRemainingTime: String {
        Self.formattedTime(for: remainingSeconds)
    }

    static func formattedTime(for seconds: Int) -> String {
        // Clamp negative input. Hours have a minimum width of two digits, but
        // are not capped at 99, so 1440 minutes displays as 24:00:00.
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
        guard !isRunning else { return }

        if remainingSeconds <= 0 {
            // Normal expiry switches phase before zero can be published. Keep
            // this guard for any other path that reaches a zero remainder.
            remainingSeconds = configuration.durationSeconds(for: phase)
        }

        // Store an absolute deadline instead of decrementing a counter on each
        // callback. Delayed callbacks cannot accumulate drift, and resuming
        // continues from the saved remainder.
        deadline = date.addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
    }

    func pause() {
        pause(at: now())
    }

    func pause(at date: Date) {
        guard isRunning else { return }

        // Update the remainder before clearing the deadline. If the deadline
        // has passed, tick performs one normal phase transition first, so zero
        // is never left on screen.
        tick(at: date)
        deadline = nil
        isRunning = false
    }

    func reset() {
        // Keep the current phase, restore its complete duration, and pause.
        isRunning = false
        deadline = nil
        remainingSeconds = configuration.durationSeconds(for: phase)
    }

    func previousPhase() {
        // In this two-phase model, both controls select the other phase.
        // Manual phase changes discard the current progress.
        switchToOtherPhase()
    }

    func nextPhase() {
        switchToOtherPhase()
    }

    func tick() {
        tick(at: now())
    }

    func tick(at date: Date) {
        guard isRunning, let deadline else { return }

        // Do not publish zero at the end of a phase. A delayed callback causes
        // one transition at the observed time, and the new phase starts there.
        if date >= deadline {
            phase = phase.next
            remainingSeconds = configuration.durationSeconds(for: phase)
            self.deadline = date.addingTimeInterval(
                TimeInterval(remainingSeconds)
            )
            return
        }

        // Round up fractional seconds so a tick immediately after play still
        // shows the full duration. The upper bound prevents a backwards clock
        // adjustment from increasing the remainder.
        let seconds = Int(ceil(deadline.timeIntervalSince(date)))
        remainingSeconds = min(
            max(0, seconds),
            configuration.durationSeconds(for: phase)
        )
    }

    private func switchToOtherPhase() {
        // Manual navigation resets the selected phase. It does not keep a
        // history, and it always pauses and clears the running deadline.
        phase = phase.next
        remainingSeconds = configuration.durationSeconds(for: phase)
        isRunning = false
        deadline = nil
    }
}
