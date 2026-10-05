import Foundation
@testable import CielBar
import XCTest

@MainActor
final class PomodoroEditorTests: XCTestCase {
    func testResetAndSkipConsumeTheDraftBeforeChangingState() {
        let manager = PomodoroManager(notificationCenter: NotificationCenter())
        let editor = PomodoroEditor(manager: manager)
        editor.begin(.minutes)
        editor.updateDraft("30")
        editor.reset()
        editor.commit()
        XCTAssertEqual(manager.remainingSeconds, 1800)
        XCTAssertEqual(manager.state, .idle)
        editor.begin(.seconds)
        editor.updateDraft("15")
        editor.skip()
        // A late focus-end / popup-close must not save the work draft to Break.
        editor.commit()
        XCTAssertEqual(manager.phase, .break)
        XCTAssertEqual(manager.remainingSeconds, 600)
        editor.skip()
        XCTAssertEqual(manager.remainingSeconds, 1815)
        manager.play()
        editor.begin(.seconds)
        XCTAssertNil(editor.editingField)
        manager.pause()
        editor.begin(.minutes)
        XCTAssertNil(editor.editingField)
    }

}
