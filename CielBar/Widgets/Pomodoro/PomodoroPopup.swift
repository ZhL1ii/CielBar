import SwiftUI

/// Controls the manager shared by the bar widget and its popup.
struct PomodoroPopup: View {
    @ObservedObject var manager: PomodoroManager

    var body: some View {
        VStack(spacing: 14) {
            PomodoroTimeView(
                phase: manager.phase,
                formattedTime: manager.formattedRemainingTime
            )
            .font(.system(size: 30, weight: .semibold))

            HStack(spacing: 12) {
                controlButton(
                    systemImageName: "backward.end.fill",
                    accessibilityLabel: "Previous phase"
                ) {
                    manager.previousPhase()
                }

                controlButton(
                    systemImageName: "arrow.counterclockwise",
                    accessibilityLabel: "Reset timer"
                ) {
                    manager.reset()
                }

                controlButton(
                    systemImageName: manager.isRunning
                        ? "pause.fill" : "play.fill",
                    accessibilityLabel: manager.isRunning
                        ? "Pause timer" : "Start timer"
                ) {
                    if manager.isRunning {
                        manager.pause()
                    } else {
                        manager.play()
                    }
                }

                controlButton(
                    systemImageName: "forward.end.fill",
                    accessibilityLabel: "Next phase"
                ) {
                    manager.nextPhase()
                }
            }
        }
        .frame(width: 200, height: 120)
        .foregroundStyle(.white)
    }

    private func controlButton(
        systemImageName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(PomodoroControlButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PomodoroControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(5)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.25 : 0.001)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct PomodoroPopup_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroPopup(manager: PomodoroManager())
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
