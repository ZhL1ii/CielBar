import SwiftUI

/// Controls the manager shared by the bar widget and its popup.
struct PomodoroPopup: View {
    @ObservedObject var manager: PomodoroManager
    @StateObject private var editor: PomodoroEditor

    init(manager: PomodoroManager) {
        self.manager = manager
        _editor = StateObject(wrappedValue: PomodoroEditor(manager: manager))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                timeField(.minutes)
                Text(":").font(.system(size: 32, weight: .semibold))
                timeField(.seconds)
            }
            HStack(spacing: 20) {
                controlButton("arrow.counterclockwise", label: "Reset timer") {
                    editor.reset()
                }
                controlButton(
                    manager.isRunning ? "pause.fill" : "play.fill",
                    label: manager.isRunning ? "Pause timer" : "Start timer"
                ) {
                    if manager.isRunning { manager.pause() } else { manager.play() }
                }
                .disabled(!manager.isRunning && !editor.canPlay)
                controlButton("forward.end.fill", label: "Skip phase") {
                    editor.skip()
                }
            }
        }
        .padding(20)
        .frame(width: 210)
        .foregroundStyle(.white)
        .disabled(!manager.isReady)
        .onReceive(NotificationCenter.default.publisher(for: .willHideWindow)) { _ in
            editor.commit()
        }
        .onReceive(NotificationCenter.default.publisher(for: .willChangeContent)) { _ in
            editor.commit()
        }
        .onDisappear { editor.commit() }
    }

    private func timeField(_ value: PomodoroEditor.Field) -> some View {
        PomodoroTimeField(
            editor: editor, field: value,
            text: editor.text(for: value), isEditable: manager.canEdit,
            isEditing: editor.editingField == value
        )
        .frame(width: 58, height: 40)
        .opacity(manager.isDimmed ? 0.8 : 1)
    }

    private func controlButton(
        _ image: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(PomodoroControlButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct PomodoroControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(5)
            .background(Color.white.opacity(configuration.isPressed ? 0.25 : 0.001))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct PomodoroPopup_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroPopup(manager: PomodoroManager())
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
