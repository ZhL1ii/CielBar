import AppKit
@testable import CielBar
import SwiftUI
import XCTest

@MainActor
final class PomodoroPopupTests: XCTestCase {
    func testCloseAndContentReplacementCommitOnlyOnceAndDoNotStopTimer() throws {
        let manager = PomodoroManager(notificationCenter: NotificationCenter())
        let (window, fields) = try showPopup(manager: manager)
        defer { window.close() }
        window.makeFirstResponder(fields[0])
        let text = try XCTUnwrap(fields[0].currentEditor() as? NSTextView)
        text.insertText("30", replacementRange: text.selectedRange())
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        NotificationCenter.default.post(name: .willChangeContent, object: nil)
        settleUI()
        XCTAssertEqual(manager.remainingSeconds, 1800)
        manager.nextPhase()
        window.makeFirstResponder(fields[1])
        let nextText = try XCTUnwrap(fields[1].currentEditor() as? NSTextView)
        nextText.insertText("15", replacementRange: nextText.selectedRange())
        window.makeFirstResponder(nil)
        settleUI()
        XCTAssertEqual(manager.remainingSeconds, 615)
        manager.play()
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        XCTAssertEqual(manager.state, .running)
        XCTAssertNotNil(manager.deadline)
    }

    private func showPopup(manager: PomodoroManager) throws -> (NSWindow, [PomodoroDigitTextField]) {
        let host = NSHostingView(rootView: PomodoroPopup(manager: manager).background(Color.black))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 210, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        settleUI()
        func descendants(_ view: NSView) -> [PomodoroDigitTextField] {
            if let field = view as? PomodoroDigitTextField { return [field] }
            return view.subviews.flatMap(descendants)
        }
        let fields = descendants(host).sorted {
            $0.convert($0.bounds, to: host).midX < $1.convert($1.bounds, to: host).midX
        }
        XCTAssertEqual(fields.count, 2)
        return (window, fields)
    }

    private func settleUI() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }
}
