import SwiftUI

/// The widget owns the manager shared with its popup, so a configuration
/// reload does not reset an active countdown.
struct PomodoroWidget: View {
    @EnvironmentObject private var configProvider: ConfigProvider
    @StateObject var manager: PomodoroManager
    @State private var rect: CGRect = .zero

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
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        rect = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        rect = newFrame
                    }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Passing the widget's manager keeps the popup and bar on the same
            // countdown.
            MenuBarPopup.show(rect: rect, id: "pomodoro") {
                PomodoroPopup(manager: manager)
            }
        }
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

/// The bar and popup share this view for their time and break-phase styling.
struct PomodoroTimeView: View {
    let phase: PomodoroPhase
    let formattedTime: String

    var body: some View {
        Text(formattedTime)
            .monospacedDigit()
            // Use the same padding in both phases so the countdown does not move
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
