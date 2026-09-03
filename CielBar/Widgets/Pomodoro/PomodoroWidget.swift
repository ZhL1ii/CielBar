import SwiftUI

/// The widget owns its manager, so a configuration reload does not reset an
/// active countdown.
struct PomodoroWidget: View {
    @EnvironmentObject private var configProvider: ConfigProvider
    @StateObject var manager: PomodoroManager

    init(configuration: PomodoroConfiguration = .defaultValue) {
        _manager = StateObject(
            wrappedValue: PomodoroManager(configuration: configuration))
    }

    var body: some View {
        PomodoroTimeView(
            phase: manager.phase,
            formattedTime: manager.formattedRemainingTime
        )
        .font(.headline)
        .fontWeight(.semibold)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onAppear {
            updateConfiguration(from: configProvider.config)
        }
        .onReceive(configProvider.$config) { config in
            updateConfiguration(from: config)
        }
    }

    private func updateConfiguration(from config: ConfigData) {
        // ConfigManager may recreate this provider when it reloads the file.
        // Apply the current snapshot and keep listening for later changes.
        manager.updateConfiguration(PomodoroConfiguration(config: config))
    }
}

/// The bar and popup use this view for the same work and break styling.
struct PomodoroTimeView: View {
    let phase: PomodoroPhase
    let formattedTime: String

    var body: some View {
        Text(formattedTime)
            .monospacedDigit()
            // Both phases use the same padding, so the countdown stays in place
            // when the break border appears or disappears.
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay {
                if phase == .break {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
    }
}
