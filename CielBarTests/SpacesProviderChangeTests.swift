@testable import CielBar
import XCTest

final class SpacesProviderChangeTests: XCTestCase {
    func testDefaultsToDebouncedRefreshWithoutFocusChange() {
        let change = SpacesProviderChange(reason: .providerEvent)

        XCTAssertEqual(change.reason, .providerEvent)
        XCTAssertNil(change.focusChange)
        XCTAssertEqual(change.refreshPolicy, .debounced)
    }

    func testRepresentsProviderFocusWithoutOptimisticFocusChange() {
        let change = SpacesProviderChange(
            reason: .providerFocusEvent,
            refreshPolicy: .immediate)

        XCTAssertEqual(change.reason, .providerFocusEvent)
        XCTAssertNil(change.focusChange)
        XCTAssertEqual(change.refreshPolicy, .immediate)
    }
}
