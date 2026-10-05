import Foundation
@testable import CielBar
import XCTest

@MainActor
final class PomodoroSettingsStoreTests: XCTestCase {
    func testRestartRestoresSettingsWithSecondsButStartsIdleWork() async {
        let suite = "CielBarTests.Pomodoro.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = PomodoroSettingsStore(suiteName: suite)
        let manager = PomodoroManager(settingsStore: store, notificationCenter: NotificationCenter())
        await manager.loadSettings()
        XCTAssertEqual(manager.remainingSeconds, 2700)
        manager.setDuration(seconds: 1815)
        manager.nextPhase()
        manager.setDuration(seconds: 37)
        manager.play()
        // Reading on the same queue waits for all previously enqueued writes.
        let saved = await store.load()
        XCTAssertEqual(saved.work, 1815)
        XCTAssertEqual(saved.break, 37)
        let restarted = PomodoroManager(
            settingsStore: PomodoroSettingsStore(suiteName: suite),
            notificationCenter: NotificationCenter())
        await restarted.loadSettings()
        XCTAssertEqual(restarted.phase, .work)
        XCTAssertEqual(restarted.state, .idle)
        XCTAssertEqual(restarted.remainingSeconds, 1815)
        restarted.nextPhase()
        XCTAssertEqual(restarted.remainingSeconds, 37)

        manager.reset()
        manager.nextPhase()
        for duration in [5999, 1815, 1, 0] { manager.setDuration(seconds: duration) }
        let latest = await store.load()
        XCTAssertEqual(latest, PomodoroDurations(work: 0, break: 37))
        let zeroRestored = PomodoroManager(
            settingsStore: PomodoroSettingsStore(suiteName: suite),
            notificationCenter: NotificationCenter())
        await zeroRestored.loadSettings()
        XCTAssertEqual(zeroRestored.remainingSeconds, 0)
        XCTAssertFalse(zeroRestored.canPlay)
        zeroRestored.play()
        XCTAssertEqual(zeroRestored.state, .idle)
    }
}
