@testable import CielBar
import XCTest

final class SpacesRefreshSchedulerTests: XCTestCase {
    func testDebouncedRequestsCoalesceIntoOneLoad() {
        let loadStarted = expectation(description: "load started")
        loadStarted.assertForOverFulfill = true
        let scheduler = SpacesRefreshScheduler(
            debounceInterval: 0.05,
            snapshotLoader: {
                loadStarted.fulfill()
                return nil
            },
            publishHandler: { _ in true })

        scheduler.requestRefresh(reason: .providerEvent)
        scheduler.requestRefresh(reason: .providerEvent)

        wait(for: [loadStarted], timeout: 0.2)
    }

    func testImmediateRequestStartsWithoutDebounceDelay() {
        let loadStarted = expectation(description: "immediate load started")
        let startTime = Date()
        let elapsedLock = NSLock()
        var elapsed: TimeInterval = 0
        let scheduler = SpacesRefreshScheduler(
            debounceInterval: 0.5,
            snapshotLoader: {
                elapsedLock.lock()
                elapsed = Date().timeIntervalSince(startTime)
                elapsedLock.unlock()
                loadStarted.fulfill()
                return nil
            },
            publishHandler: { _ in true })

        scheduler.requestRefresh(
            reason: .providerFocusEvent,
            policy: .immediate)

        wait(for: [loadStarted], timeout: 0.1)
        elapsedLock.lock()
        XCTAssertLessThan(elapsed, 0.1)
        elapsedLock.unlock()
    }

    func testImmediateRequestSupersedesQueuedDebounce() {
        let firstLoad = expectation(description: "immediate load")
        let unexpectedSecondLoad = expectation(description: "cancelled debounce")
        unexpectedSecondLoad.isInverted = true
        let countLock = NSLock()
        var loadCount = 0
        let scheduler = SpacesRefreshScheduler(
            debounceInterval: 0.1,
            snapshotLoader: {
                countLock.lock()
                loadCount += 1
                let currentLoad = loadCount
                countLock.unlock()
                if currentLoad == 1 {
                    firstLoad.fulfill()
                } else {
                    unexpectedSecondLoad.fulfill()
                }
                return nil
            },
            publishHandler: { _ in true })

        scheduler.requestRefresh(reason: .providerEvent)
        scheduler.requestRefresh(
            reason: .providerFocusEvent,
            policy: .immediate)

        wait(for: [firstLoad, unexpectedSecondLoad], timeout: 0.2)
    }

    func testImmediateRequestDuringLoadCreatesOneImmediateFollowUp() {
        let firstLoadStarted = expectation(description: "first load started")
        let secondLoadStarted = expectation(description: "immediate follow-up")
        secondLoadStarted.assertForOverFulfill = true
        let releaseFirstLoad = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var loadCount = 0
        var activeLoads = 0
        var maximumActiveLoads = 0
        var secondLoadElapsed: TimeInterval = 0
        var firstLoadReleasedAt: Date?
        let scheduler = SpacesRefreshScheduler(
            debounceInterval: 0.2,
            snapshotLoader: {
                stateLock.lock()
                loadCount += 1
                let currentLoad = loadCount
                activeLoads += 1
                maximumActiveLoads = max(maximumActiveLoads, activeLoads)
                stateLock.unlock()

                if currentLoad == 1 {
                    firstLoadStarted.fulfill()
                    releaseFirstLoad.wait()
                } else {
                    stateLock.lock()
                    secondLoadElapsed = Date().timeIntervalSince(
                        firstLoadReleasedAt!)
                    stateLock.unlock()
                    secondLoadStarted.fulfill()
                }

                stateLock.lock()
                activeLoads -= 1
                stateLock.unlock()
                return nil
            },
            publishHandler: { _ in true })

        scheduler.requestRefresh(reason: .providerEvent, policy: .immediate)
        wait(for: [firstLoadStarted], timeout: 0.1)
        scheduler.requestRefresh(reason: .providerEvent)
        scheduler.requestRefresh(
            reason: .providerFocusEvent,
            policy: .immediate)
        stateLock.lock()
        firstLoadReleasedAt = Date()
        stateLock.unlock()
        releaseFirstLoad.signal()

        wait(for: [secondLoadStarted], timeout: 0.1)
        stateLock.lock()
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(maximumActiveLoads, 1)
        XCTAssertLessThan(secondLoadElapsed, 0.1)
        stateLock.unlock()
    }
}
