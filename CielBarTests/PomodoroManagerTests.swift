import AppKit
@testable import CielBar
import XCTest

@MainActor
final class PomodoroManagerTests: XCTestCase {
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

    func testConfigurationAcceptsValidBoundariesAndFallsBackPerField() {
        let configuration = PomodoroConfiguration(config: [
            "work-duration": .int(1),
            "break-duration": .int(1440),
        ])

        XCTAssertEqual(configuration.workDurationMinutes, 1)
        XCTAssertEqual(configuration.breakDurationMinutes, 1440)

        let invalidConfiguration = PomodoroConfiguration(config: [
            "work-duration": .int(0),
            "break-duration": .int(1441),
        ])

        XCTAssertEqual(
            invalidConfiguration.workDurationMinutes,
            PomodoroConfiguration.defaultWorkDurationMinutes)
        XCTAssertEqual(
            invalidConfiguration.breakDurationMinutes,
            PomodoroConfiguration.defaultBreakDurationMinutes)
    }

    func testConfigurationFallsBackForMissingAndNonIntegerValues() {
        let missingConfiguration = PomodoroConfiguration(config: [:])
        XCTAssertEqual(
            missingConfiguration,
            .defaultValue)

        let missingBreakConfiguration = PomodoroConfiguration(config: [
            "work-duration": .int(30),
        ])
        XCTAssertEqual(missingBreakConfiguration.workDurationMinutes, 30)
        XCTAssertEqual(
            missingBreakConfiguration.breakDurationMinutes,
            PomodoroConfiguration.defaultBreakDurationMinutes)

        let missingWorkConfiguration = PomodoroConfiguration(config: [
            "break-duration": .int(20),
        ])
        XCTAssertEqual(
            missingWorkConfiguration.workDurationMinutes,
            PomodoroConfiguration.defaultWorkDurationMinutes)
        XCTAssertEqual(missingWorkConfiguration.breakDurationMinutes, 20)

        let invalidValues: [TOMLValue] = [
            .string("45"),
            .bool(true),
            .double(45.0),
            .array([.int(45)]),
            .dictionary([:]),
            .null,
        ]

        for value in invalidValues {
            let configuration = PomodoroConfiguration(config: [
                "work-duration": value,
                "break-duration": .int(20),
            ])

            XCTAssertEqual(
                configuration.workDurationMinutes,
                PomodoroConfiguration.defaultWorkDurationMinutes)
            XCTAssertEqual(configuration.breakDurationMinutes, 20)
        }

        for invalidValue in [-1, 0, 1_441] {
            let configuration = PomodoroConfiguration(config: [
                "work-duration": .int(30),
                "break-duration": .int(invalidValue),
            ])

            XCTAssertEqual(configuration.workDurationMinutes, 30)
            XCTAssertEqual(
                configuration.breakDurationMinutes,
                PomodoroConfiguration.defaultBreakDurationMinutes)
        }
    }

    func testTimeFormattingUsesFixedHoursMinutesAndSeconds() {
        XCTAssertEqual(
            PomodoroManager.formattedTime(for: 0),
            "00:00:00")
        XCTAssertEqual(
            PomodoroManager.formattedTime(for: 1),
            "00:00:01")
        XCTAssertEqual(
            PomodoroManager.formattedTime(for: 3_599),
            "00:59:59")
        XCTAssertEqual(
            PomodoroManager.formattedTime(for: 3_600),
            "01:00:00")
        XCTAssertEqual(
            PomodoroManager.formattedTime(for: 86_400),
            "24:00:00")
        XCTAssertEqual(
            PomodoroManager.formattedTime(for: -1),
            "00:00:00")
    }

    func testInitialStateIsPausedWorkWithFullDuration() {
        let (manager, _) = makeManager(workMinutes: 45, breakMinutes: 10)

        XCTAssertEqual(manager.phase, .work)
        XCTAssertEqual(manager.remainingSeconds, 2_700)
        XCTAssertEqual(manager.formattedRemainingTime, "00:45:00")
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
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
        XCTAssertNil(manager.deadline)

        clock.advance(by: 100)
        manager.play()
        XCTAssertEqual(
            manager.deadline,
            clock.current.addingTimeInterval(2_690))

        clock.advance(by: 5.5)
        manager.tick()
        XCTAssertEqual(manager.remainingSeconds, 2_685)
    }

    func testResetRestoresFullDurationAndPausesInEitherPhase() {
        let (manager, _) = makeManager(workMinutes: 45, breakMinutes: 10)

        manager.reset()
        XCTAssertEqual(manager.phase, .work)
        XCTAssertEqual(manager.remainingSeconds, 2_700)
        XCTAssertFalse(manager.isRunning)

        manager.nextPhase()
        manager.play()
        manager.reset()

        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 600)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
    }

    func testPreviousAndNextTogglePhaseAndPauseWithFullDuration() {
        let (manager, _) = makeManager(workMinutes: 45, breakMinutes: 10)

        manager.nextPhase()
        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 600)
        XCTAssertFalse(manager.isRunning)

        manager.play()
        manager.previousPhase()
        XCTAssertEqual(manager.phase, .work)
        XCTAssertEqual(manager.remainingSeconds, 2_700)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)

        manager.previousPhase()
        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 600)
        XCTAssertFalse(manager.isRunning)
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

    func testWakeBeforeDeadlineCountsSleepAndContinuesRunning() {
        let (manager, clock) = makeManager(workMinutes: 1, breakMinutes: 2)
        let start = clock.current
        manager.play()

        clock.advance(by: 15)
        manager.handleSystemWillSleep(at: clock.current)
        XCTAssertEqual(manager.remainingSeconds, 45)

        clock.advance(by: 20)
        manager.handleSystemDidWake(at: clock.current)

        XCTAssertEqual(manager.phase, .work)
        XCTAssertEqual(manager.remainingSeconds, 25)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(
            manager.deadline,
            start.addingTimeInterval(60))
    }

    func testWakeAtDeadlineSwitchesOnceAndPauses() {
        let (manager, clock) = makeManager(workMinutes: 1, breakMinutes: 2)
        manager.play()
        manager.handleSystemWillSleep(at: clock.current)

        clock.advance(by: 60)
        manager.handleSystemDidWake(at: clock.current)

        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 120)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)

        manager.handleSystemDidWake(at: clock.current.addingTimeInterval(60))
        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 120)
        XCTAssertFalse(manager.isRunning)
    }

    func testWakeAfterDeadlineSwitchesOnceAndPauses() {
        let (manager, clock) = makeManager(workMinutes: 1, breakMinutes: 2)
        manager.play()
        manager.handleSystemWillSleep(at: clock.current)

        clock.advance(by: 5 * 60)
        manager.handleSystemDidWake(at: clock.current)

        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 120)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
    }

    func testTickDoesNotTransitionWhileSleeping() {
        let (manager, clock) = makeManager(workMinutes: 1, breakMinutes: 2)
        manager.play()
        manager.handleSystemWillSleep(at: clock.current)

        clock.advance(by: 61)
        manager.tick()

        XCTAssertEqual(manager.phase, .work)
        XCTAssertEqual(manager.remainingSeconds, 60)
        XCTAssertTrue(manager.isRunning)

        manager.handleSystemDidWake(at: clock.current)
        XCTAssertEqual(manager.phase, .break)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
    }

    func testPausedManagerKeepsStateAcrossSleepAndWake() {
        let (manager, clock) = makeManager(workMinutes: 1, breakMinutes: 2)
        manager.nextPhase()
        let phaseBeforeSleep = manager.phase
        let remainingBeforeSleep = manager.remainingSeconds

        manager.handleSystemWillSleep(at: clock.current)
        clock.advance(by: 5 * 60)
        manager.handleSystemDidWake(at: clock.current)

        XCTAssertEqual(manager.phase, phaseBeforeSleep)
        XCTAssertEqual(manager.remainingSeconds, remainingBeforeSleep)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
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
        clock.advance(by: 61)
        notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil)

        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 120)
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.deadline)
    }

    private func makeManager(
        workMinutes: Int,
        breakMinutes: Int,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> (PomodoroManager, TestClock) {
        let clock = TestClock()
        let configuration = PomodoroConfiguration(
            workDurationMinutes: workMinutes,
            breakDurationMinutes: breakMinutes)
        let manager = PomodoroManager(
            configuration: configuration,
            now: { clock.current },
            notificationCenter: notificationCenter)
        return (manager, clock)
    }
}
