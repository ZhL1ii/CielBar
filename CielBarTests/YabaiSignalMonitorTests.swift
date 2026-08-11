@testable import CielBar
import Darwin
import XCTest

final class YabaiSignalMonitorTests: XCTestCase {
    func testFocusEventsUseSIGUSR2AndOtherEventsUseSIGUSR1() {
        let processIdentifier: Int32 = 4242

        XCTAssertEqual(
            YabaiSignalMonitor.focusEvents,
            ["space_changed", "window_focused"])
        XCTAssertTrue(
            Set(YabaiSignalMonitor.focusEvents).isDisjoint(
                with: YabaiSignalMonitor.otherMonitoredEvents))

        for event in YabaiSignalMonitor.focusEvents {
            XCTAssertEqual(
                YabaiSignalMonitor.action(
                    for: event, processIdentifier: processIdentifier),
                "/bin/kill -USR2 \(processIdentifier)")
        }
        for event in YabaiSignalMonitor.otherMonitoredEvents {
            XCTAssertEqual(
                YabaiSignalMonitor.action(
                    for: event, processIdentifier: processIdentifier),
                "/bin/kill -USR1 \(processIdentifier)")
        }
    }

    func testSIGUSR1ProducesDebouncedGenericProviderChange() {
        let change = YabaiSignalMonitor.providerChange(for: SIGUSR1)

        XCTAssertEqual(change.reason, .providerEvent)
        XCTAssertNil(change.focusChange)
        XCTAssertEqual(change.refreshPolicy, .debounced)
    }

    func testSIGUSR2ProducesImmediateFocusProviderChange() {
        let change = YabaiSignalMonitor.providerChange(for: SIGUSR2)

        XCTAssertEqual(change.reason, .providerFocusEvent)
        XCTAssertNil(change.focusChange)
        XCTAssertEqual(change.refreshPolicy, .immediate)
    }
}
