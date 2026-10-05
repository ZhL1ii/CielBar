import Combine
import Foundation

/// One active field draft, shared by keyboard, focus, close and control actions.
@MainActor
final class PomodoroEditor: ObservableObject {
    enum Field {
        case minutes
        case seconds

        var maximum: Int { self == .minutes ? 99 : 59 }
        var accessibilityLabel: String { self == .minutes ? "Minutes" : "Seconds" }
    }

    @Published private(set) var editingField: Field?
    @Published private(set) var draft = ""
    let manager: PomodoroManager

    init(manager: PomodoroManager) {
        self.manager = manager
    }

    var canPlay: Bool { manager.canPlay && editingField == nil }

    func text(for field: Field) -> String {
        if editingField == field { return draft }
        return String(format: "%02d", value(for: field))
    }

    func begin(_ field: Field) {
        guard manager.canEdit, editingField != field else { return }
        commit()
        draft = text(for: field)
        editingField = field
    }

    func updateDraft(_ text: String) {
        guard editingField != nil else { return }
        draft = String(text.filter { $0 >= "0" && $0 <= "9" }.prefix(2))
    }

    func adjust(by step: Int) {
        guard let field = editingField else { return }
        let value = min(max((Int(draft) ?? 0) + step, 0), field.maximum)
        draft = String(format: "%02d", value)
    }

    func commit() {
        guard let field = editingField else { return }
        let value = min(Int(draft) ?? 0, field.maximum)
        let seconds = field == .minutes
            ? value * 60 + manager.remainingSeconds % 60
            : manager.remainingSeconds / 60 * 60 + value
        // Clear first: a subsequent focus-end/close callback is a no-op.
        editingField = nil
        draft = ""
        manager.setDuration(seconds: seconds)
    }

    func cancel() {
        editingField = nil
        draft = ""
    }

    func reset() {
        commit()
        manager.reset()
    }

    func skip() {
        commit()
        manager.nextPhase()
    }

    private func value(for field: Field) -> Int {
        field == .minutes ? manager.remainingSeconds / 60 : manager.remainingSeconds % 60
    }
}
