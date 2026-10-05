import CoreFoundation
import Foundation

/// Only phase settings are persisted. All defaults access happens on this
/// serial queue; enqueuing saves synchronously preserves submission order.
final class PomodoroSettingsStore {
    static let shared = PomodoroSettingsStore()
    static let workKey = "pomodoro.workDurationSeconds"
    static let breakKey = "pomodoro.breakDurationSeconds"

    private let queue = DispatchQueue(label: "CielBar.Pomodoro.settings", qos: .utility)
    private let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    func load() async -> PomodoroDurations {
        await withCheckedContinuation { continuation in
            queue.async {
                let defaults = self.defaults()
                continuation.resume(returning: PomodoroDurations(
                    work: Self.validated(
                        defaults.object(forKey: Self.workKey), fallback: PomodoroDurations.defaultValue.work),
                    break: Self.validated(
                        defaults.object(forKey: Self.breakKey), fallback: PomodoroDurations.defaultValue.break)
                ))
            }
        }
    }

    func save(seconds: Int, for phase: PomodoroPhase) {
        guard PomodoroDurations.validRange.contains(seconds) else { return }
        queue.async {
            self.defaults().set(seconds, forKey: phase == .work ? Self.workKey : Self.breakKey)
        }
    }

    private func defaults() -> UserDefaults {
        if let suiteName { return UserDefaults(suiteName: suiteName)! }
        return .standard
    }

    private static func validated(_ value: Any?, fallback: Int) -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              (Int64(PomodoroDurations.validRange.lowerBound)...Int64(PomodoroDurations.validRange.upperBound))
                .contains(number.int64Value)
        else { return fallback }
        return number.intValue
    }
}
