import SwiftUI

/// The widget owns the manager shared with its popup, so a configuration
/// reload does not reset an active countdown.
struct PomodoroWidget: View {
    @StateObject var manager: PomodoroManager
    @State private var rect: CGRect = .zero

    init() {
        _manager = StateObject(wrappedValue: PomodoroManager(settingsStore: .shared))
    }

    var body: some View {
        PomodoroProgressView(
            minutes: manager.barMinutes,
            remainingRatio: manager.remainingRatio,
            isDimmed: manager.isDimmed
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(manager.phase == .work ? "Work timer" : "Break timer")
        .accessibilityValue(manager.formattedRemainingTime)
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
        .task { await manager.loadSettings() }
    }
}

/// A single remaining arc, starting at noon and retreating clockwise.
struct PomodoroProgressView: View {
    let minutes: String
    let remainingRatio: Double
    let isDimmed: Bool

    var body: some View {
        ZStack {
            if remainingRatio > 0 {
                Circle()
                    .trim(from: 0, to: remainingRatio)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
            }
            Text(minutes)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .opacity(isDimmed ? 0.8 : 1)
        }
        .frame(width: 24, height: 24)
        .padding(.horizontal, 3)
    }
}
