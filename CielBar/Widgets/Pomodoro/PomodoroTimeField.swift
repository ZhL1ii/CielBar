import AppKit
import SwiftUI

/// AppKit's field editor supplies selection and key bindings inside the panel.
struct PomodoroTimeField: NSViewRepresentable {
    @ObservedObject var editor: PomodoroEditor
    let field: PomodoroEditor.Field
    let text: String
    let isEditable: Bool
    let isEditing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> PomodoroDigitTextField {
        let view = PomodoroDigitTextField()
        view.isBordered = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.alignment = .center
        view.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
        view.textColor = .white
        view.delegate = context.coordinator
        view.setAccessibilityLabel(field.accessibilityLabel)
        view.onBegin = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.editor.begin(coordinator.parent.field)
        }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: PomodoroDigitTextField, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEditable
        view.isSelectable = isEditable
        view.setAccessibilityEnabled(isEditable)
        // A control action or popup close may have already consumed this draft.
        if !isEditing, view.currentEditor() != nil {
            view.window?.makeFirstResponder(nil)
        }
        if view.stringValue != text { view.stringValue = text }
    }

    static func dismantleNSView(_ view: PomodoroDigitTextField, coordinator: Coordinator) {
        view.delegate = nil
        view.onBegin = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PomodoroTimeField

        init(parent: PomodoroTimeField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.editor.begin(parent.field)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextField else { return }
            parent.editor.updateDraft(view.stringValue)
            let filtered = parent.editor.text(for: parent.field)
            if let textView = view.currentEditor() as? NSTextView, textView.string != filtered {
                let position = min(textView.selectedRange().location, filtered.utf16.count)
                textView.string = filtered
                textView.setSelectedRange(NSRange(location: position, length: 0))
            }
            view.stringValue = filtered
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.editor.editingField == parent.field { parent.editor.commit() }
            (notification.object as? NSTextField)?.stringValue = parent.editor.text(for: parent.field)
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy command: Selector
        ) -> Bool {
            switch command {
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                parent.editor.adjust(by: command == #selector(NSResponder.moveUp(_:)) ? 1 : -1)
                textView.string = parent.editor.text(for: parent.field)
                (control as? NSTextField)?.stringValue = textView.string
                textView.selectAll(nil)
            case #selector(NSResponder.insertNewline(_:)):
                parent.editor.commit()
                control.window?.makeFirstResponder(nil)
            case #selector(NSResponder.insertTab(_:)):
                parent.editor.commit()
                control.window?.recalculateKeyViewLoop()
                control.window?.selectKeyView(following: control)
            case #selector(NSResponder.insertBacktab(_:)):
                parent.editor.commit()
                control.window?.recalculateKeyViewLoop()
                control.window?.selectKeyView(preceding: control)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.editor.cancel()
                control.window?.makeFirstResponder(nil)
            default:
                return false
            }
            return true
        }
    }
}

final class PomodoroDigitTextField: NSTextField {
    var onBegin: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, isEditable {
            onBegin?()
            currentEditor()?.selectAll(nil)
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditable else { return }
        onBegin?()
        super.mouseDown(with: event)
        currentEditor()?.selectAll(nil)
    }
}
