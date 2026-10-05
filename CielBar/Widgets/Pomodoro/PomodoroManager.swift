import AppKit
import Combine
import Foundation

enum PomodoroPhase: Equatable {
    case work
    case `break`

    var next: PomodoroPhase { self == .work ? .break : .work }
}

enum PomodoroState: Equatable {
    case idle
    case running
    case paused
}

struct PomodoroDurations: Equatable {
    static let validRange = 0...5999
    static let defaultValue = PomodoroDurations(work: 2700, break: 600)

    var work: Int
    var `break`: Int

    func seconds(for phase: PomodoroPhase) -> Int {
        phase == .work ? work : `break`
    }

    mutating func set(seconds: Int, for phase: PomodoroPhase) {
        switch phase {
        case .work: work = seconds
        case .break: `break` = seconds
        }
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .work
    @Published private(set) var state: PomodoroState = .idle
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var totalSeconds: Int
    @Published private(set) var isReady: Bool

    private(set) var durations: PomodoroDurations
    private(set) var deadline: Date?

    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let settingsStore: PomodoroSettingsStore?
    private var isLoadingSettings = false
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var isSleeping = false
    private var wasRunningBeforeSleep = false

    init(
        durations: PomodoroDurations = .defaultValue,
        settingsStore: PomodoroSettingsStore? = nil,
        now: @escaping () -> Date = { Date() },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.durations = durations
        self.settingsStore = settingsStore
        isReady = settingsStore == nil
        self.now = now
        self.notificationCenter = notificationCenter
        remainingSeconds = durations.work
        totalSeconds = durations.work
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
        if let sleepObserver { notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { notificationCenter.removeObserver(wakeObserver) }
    }

    var isRunning: Bool { state == .running }
    var canEdit: Bool { isReady && state == .idle }
    var canPlay: Bool { isReady && !isRunning && remainingSeconds > 0 && !isSleeping }
    var formattedRemainingTime: String { Self.formattedTime(for: remainingSeconds) }
    var barMinutes: String { String(format: "%02d", remainingSeconds / 60) }
    var remainingRatio: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(totalSeconds), 0), 1)
    }
    var isDimmed: Bool { phase == .break || state == .paused }

    static func formattedTime(for seconds: Int) -> String {
        let value = min(max(0, seconds), PomodoroDurations.validRange.upperBound)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    func loadSettings() async {
        guard !isReady, !isLoadingSettings, let settingsStore else { return }
        isLoadingSettings = true
        let saved = await settingsStore.load()
        durations = saved
        restoreIdlePhase()
        isReady = true
        isLoadingSettings = false
    }

    @discardableResult
    func setDuration(seconds: Int) -> Bool {
        guard canEdit, PomodoroDurations.validRange.contains(seconds) else { return false }
        durations.set(seconds: seconds, for: phase)
        remainingSeconds = seconds
        totalSeconds = seconds
        settingsStore?.save(seconds: seconds, for: phase)
        return true
    }

    func play() { play(at: now()) }

    func play(at date: Date) {
        guard canPlay else { return }
        if state == .idle { totalSeconds = remainingSeconds }
        // Resume preserves the original total, but establishes a new deadline.
        deadline = date.addingTimeInterval(TimeInterval(remainingSeconds))
        state = .running
        startTimer()
    }

    func pause() { pause(at: now()) }

    func pause(at date: Date) {
        guard isRunning else { return }
        if isSleeping {
            if let deadline { updateRemainingSeconds(at: date, deadline: deadline) }
        } else {
            tick(at: date)
        }
        deadline = nil
        // A zero-duration target reached by tick stays Idle.
        if state == .running { state = .paused }
        wasRunningBeforeSleep = false
        stopTimer()
    }

    func reset() {
        guard isReady else { return }
        restoreIdlePhase()
    }

    func nextPhase() {
        guard isReady else { return }
        phase = phase.next
        restoreIdlePhase()
    }

    func tick() { tick(at: now()) }

    func tick(at date: Date) {
        guard isRunning, !isSleeping, let deadline else { return }
        if date >= deadline {
            // Delayed callbacks transition once, starting the new phase now.
            phase = phase.next
            restoreIdlePhase()
            play(at: date)
            return
        }
        updateRemainingSeconds(at: date, deadline: deadline)
    }

    private func restoreIdlePhase() {
        remainingSeconds = durations.seconds(for: phase)
        totalSeconds = remainingSeconds
        state = .idle
        deadline = nil
        wasRunningBeforeSleep = false
        stopTimer()
    }

    private func startMonitoring() {
        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleSystemWillSleep(at: self.now())
            }
        }
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
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
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
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
            // Sleep counts as elapsed time, but never catches up multiple phases.
            phase = phase.next
            restoreIdlePhase()
            return
        }
        updateRemainingSeconds(at: date, deadline: deadline)
        startTimer()
    }

    private func updateRemainingSeconds(at date: Date, deadline: Date) {
        let seconds = Int(ceil(deadline.timeIntervalSince(date)))
        remainingSeconds = min(max(0, seconds), totalSeconds)
    }
}
