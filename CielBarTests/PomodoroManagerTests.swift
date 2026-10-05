import AppKit
@testable import CielBar
import XCTest

@MainActor
final class PomodoroManagerTests: XCTestCase {
    func testExpiryIntoZeroDurationStaysIdleAndDoesNotSkipIt() {
        let clock = TestClock()
        let manager = PomodoroManager(
            durations: PomodoroDurations(work: 1, break: 0),
            now: { clock.current }, notificationCenter: NotificationCenter())
        manager.play()
        clock.advance(by: 1)
        manager.tick()
        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.remainingSeconds, 0)
        XCTAssertEqual(manager.totalSeconds, 0)
        XCTAssertNil(manager.deadline)
        manager.play()
        manager.tick(at: .distantFuture)
        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.state, .idle)
    }

    // A mutable clock keeps transitions deterministic without waiting on real
    // time.
    private final class TestClock {
        var current: Date

        init() {
            current = Date(timeIntervalSince1970: 1_000_000)
        }

        func advance(by interval: TimeInterval) {
            current = current.addingTimeInterval(interval)
        }
    }

    func testPlayTickPauseAndResumeUseTheInjectedClock() {
        let (manager, clock) = makeManager(workMinutes: 45, breakMinutes: 10)
        let start = clock.current

        manager.play()

        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(
            manager.deadline,
            start.addingTimeInterval(2_700))

        clock.advance(by: 10.25)
        manager.tick()
        XCTAssertEqual(manager.remainingSeconds, 2_690)

        manager.pause()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.remainingSeconds, 2_690)
        XCTAssertEqual(manager.totalSeconds, 2_700)
        XCTAssertNil(manager.deadline)

        clock.advance(by: 100)
        manager.play()
        XCTAssertEqual(
            manager.deadline,
            clock.current.addingTimeInterval(2_690))

        clock.advance(by: 5.5)
        manager.tick()
        XCTAssertEqual(manager.remainingSeconds, 2_685)
        XCTAssertEqual(manager.totalSeconds, 2_700)
    }

    func testExpirySwitchesOnceToTheOtherFullPhaseAndContinuesRunning() {
        let (manager, clock) = makeManager(workMinutes: 1, breakMinutes: 2)
        manager.play()

        clock.advance(by: 60)
        manager.tick()

        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 120)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(
            manager.deadline,
            clock.current.addingTimeInterval(120))

        clock.advance(by: 121.5)
        manager.tick()

        XCTAssertEqual(manager.phase, .work)
        XCTAssertEqual(manager.remainingSeconds, 60)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(
            manager.deadline,
            clock.current.addingTimeInterval(60))
    }

    func testSystemNotificationsDriveSleepRecovery() {
        let notificationCenter = NotificationCenter()
        let (manager, clock) = makeManager(
            workMinutes: 1,
            breakMinutes: 2,
            notificationCenter: notificationCenter)
        manager.play()

        notificationCenter.post(
            name: NSWorkspace.willSleepNotification,
            object: nil)
        clock.advance(by: 5 * 60)
        manager.tick()
        XCTAssertEqual(manager.phase, .work)
        notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil)

        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 120)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
        notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil)
        XCTAssertEqual(manager.phase, .break)
    }

    private func makeManager(
        workMinutes: Int,
        breakMinutes: Int,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> (PomodoroManager, TestClock) {
        let clock = TestClock()
        let durations = PomodoroDurations(
            work: workMinutes * 60,
            break: breakMinutes * 60)
        let manager = PomodoroManager(
            durations: durations,
            now: { clock.current },
            notificationCenter: notificationCenter)
        return (manager, clock)
    }
}
