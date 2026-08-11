@testable import CielBar
import XCTest

final class SpacesFocusCoordinatorTests: XCTestCase {
    func testFocusRequestReturnsWithoutWaitingForWindowDelay() {
        let workScheduled = expectation(description: "window focus scheduled")
        let coordinator = SpacesFocusCoordinator(
            delay: 1,
            commandHandler: { _ in true },
            refreshHandler: { _ in },
            scheduleDelayedWork: { _ in
                workScheduled.fulfill()
            })
        let startTime = Date()

        coordinator.focusWindow(windowID: "42", inSpaceWithID: "2")

        XCTAssertLessThan(Date().timeIntervalSince(startTime), 0.1)
        wait(for: [workScheduled], timeout: 0.1)
    }

    func testFocusesSpaceBeforeWindowOffMainThread() {
        let spaceFocused = expectation(description: "space focused")
        let windowFocused = expectation(description: "window focused")
        let stateLock = NSLock()
        var commands: [SpacesFocusCommand] = []
        var ranOnMainThread = false
        var refreshReasons: [SpacesChangeReason] = []
        let coordinator = SpacesFocusCoordinator(
            delay: 0.01,
            commandHandler: { command in
                stateLock.lock()
                commands.append(command)
                ranOnMainThread = ranOnMainThread || Thread.isMainThread
                stateLock.unlock()

                switch command {
                case .space:
                    spaceFocused.fulfill()
                case .window:
                    windowFocused.fulfill()
                }
                return true
            },
            refreshHandler: { reason in
                stateLock.lock()
                refreshReasons.append(reason)
                stateLock.unlock()
            })

        coordinator.focusWindow(windowID: "42", inSpaceWithID: "2")

        wait(for: [spaceFocused, windowFocused], timeout: 0.2)
        stateLock.lock()
        XCTAssertEqual(commands, [.space("2"), .window("42")])
        XCTAssertEqual(refreshReasons, [.focusSpace, .focusWindow])
        XCTAssertFalse(ranOnMainThread)
        stateLock.unlock()
    }

    func testNewRequestCancelsPendingWindowFocus() {
        let firstWindowFocusScheduled = expectation(
            description: "first window focus scheduled")
        let secondSpaceFocused = expectation(description: "second space focused")
        let secondWindowFocusScheduled = expectation(
            description: "second window focus scheduled")
        let coordinationQueue = DispatchQueue(
            label: "moe.ciel.CielBar.tests.spaces-focus-coordinator")
        let stateLock = NSLock()
        var commands: [SpacesFocusCommand] = []
        var refreshReasons: [SpacesChangeReason] = []
        var scheduledWorkItems: [DispatchWorkItem] = []
        let coordinator = SpacesFocusCoordinator(
            coordinationQueue: coordinationQueue,
            commandHandler: { command in
                stateLock.lock()
                commands.append(command)
                stateLock.unlock()

                if command == .space("2") {
                    secondSpaceFocused.fulfill()
                }
                return true
            },
            refreshHandler: { reason in
                stateLock.lock()
                refreshReasons.append(reason)
                stateLock.unlock()
            },
            scheduleDelayedWork: { workItem in
                stateLock.lock()
                scheduledWorkItems.append(workItem)
                let scheduledCount = scheduledWorkItems.count
                stateLock.unlock()

                if scheduledCount == 1 {
                    firstWindowFocusScheduled.fulfill()
                } else {
                    secondWindowFocusScheduled.fulfill()
                }
            })

        coordinator.focusWindow(windowID: "11", inSpaceWithID: "1")
        wait(for: [firstWindowFocusScheduled], timeout: 0.1)

        coordinator.focusWindow(windowID: "22", inSpaceWithID: "2")
        wait(
            for: [secondSpaceFocused, secondWindowFocusScheduled],
            timeout: 0.1)

        stateLock.lock()
        let firstWindowFocus = scheduledWorkItems[0]
        let secondWindowFocus = scheduledWorkItems[1]
        stateLock.unlock()
        XCTAssertTrue(firstWindowFocus.isCancelled)

        coordinationQueue.sync {
            secondWindowFocus.perform()
        }

        stateLock.lock()
        XCTAssertEqual(
            commands,
            [.space("1"), .space("2"), .window("22")])
        XCTAssertEqual(
            refreshReasons,
            [.focusSpace, .focusSpace, .focusWindow])
        stateLock.unlock()
    }
}
