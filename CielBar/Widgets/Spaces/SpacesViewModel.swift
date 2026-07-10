import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    private let fallbackRefreshInterval: TimeInterval = 10
    private var provider: AnySpacesProvider?
    private var fallbackRefreshTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var systemWakeObserver: NSObjectProtocol?
    private lazy var refreshScheduler = SpacesRefreshScheduler(
        snapshotLoader: { [weak self] in
            self?.loadSpacesSnapshot() ?? []
        },
        publishHandler: { [weak self] spaces in
            self?.spaces = spaces
        })

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        } else {
            provider = nil
        }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        requestRefresh(reason: "initial")

        fallbackRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: fallbackRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.requestRefresh(reason: "fallback-poll")
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestRefresh(reason: "app-activated")
        }

        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestRefresh(reason: "system-wake")
        }
    }

    private func stopMonitoring() {
        fallbackRefreshTimer?.invalidate()
        fallbackRefreshTimer = nil

        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }

        if let systemWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                systemWakeObserver)
            self.systemWakeObserver = nil
        }

        refreshScheduler.stop()
    }

    func requestRefresh(reason: String) {
        refreshScheduler.requestRefresh(reason: reason)
    }

    private func loadSpacesSnapshot() -> [AnySpace] {
        guard let provider,
            let spaces = provider.getSpacesWithWindows()
        else {
            return []
        }
        return spaces.sorted { $0.id < $1.id }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
            self?.requestRefresh(reason: "focus-space")

            if needWindowFocus {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + 0.2
                ) { [weak self] in
                    self?.requestRefresh(reason: "focus-space-window")
                }
            }
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.provider?.focusWindow(windowId: String(window.id))
            self?.requestRefresh(reason: "focus-window")
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
