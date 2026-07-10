import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    private enum ProviderKind {
        case yabai
        case aerospace

        init?(application: NSRunningApplication) {
            switch application.localizedName?.lowercased() {
            case "yabai":
                self = .yabai
            case "aerospace":
                self = .aerospace
            default:
                return nil
            }
        }
    }

    @Published var spaces: [AnySpace] = []
    private let fallbackRefreshInterval: TimeInterval = 10
    private let providerStateLock = NSLock()
    private var provider: AnySpacesProvider?
    private var providerKind: ProviderKind?
    private var providerGeneration = 0
    private var fallbackRefreshTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var systemWakeObserver: NSObjectProtocol?
    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminationObserver: NSObjectProtocol?
    private lazy var refreshScheduler = SpacesRefreshScheduler(
        snapshotLoader: { [weak self] in
            self?.loadSpacesSnapshot()
        },
        publishHandler: { [weak self] snapshot in
            self?.publish(snapshot: snapshot) ?? false
        })

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        fallbackRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: fallbackRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.requestRefresh(reason: .fallbackPoll)
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestRefresh(reason: .appActivated)
        }

        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestRefresh(reason: .systemWake)
        }

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        appLaunchObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleApplicationLifecycleNotification(notification)
        }

        appTerminationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleApplicationLifecycleNotification(notification)
        }

        updateProviderSelection(reason: .initial)
    }

    private func stopMonitoring() {
        let currentProvider = replaceProviderState(
            provider: nil, kind: nil).oldProvider
        currentProvider?.stopMonitoring()

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

        if let appLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                appLaunchObserver)
            self.appLaunchObserver = nil
        }

        if let appTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                appTerminationObserver)
            self.appTerminationObserver = nil
        }

        refreshScheduler.stop()
    }

    func requestRefresh(reason: SpacesChangeReason) {
        refreshScheduler.requestRefresh(reason: reason.rawValue)
    }

    private func loadSpacesSnapshot() -> SpacesRefreshSnapshot? {
        let providerState = currentProviderState()
        let spaces = providerState.provider?.getSpacesWithWindows()?
            .sorted { $0.id < $1.id } ?? []

        guard isCurrentProviderGeneration(providerState.generation) else {
            return nil
        }
        return SpacesRefreshSnapshot(
            spaces: spaces,
            providerGeneration: providerState.generation)
    }

    private func publish(snapshot: SpacesRefreshSnapshot) -> Bool {
        guard isCurrentProviderGeneration(snapshot.providerGeneration) else {
            return false
        }
        spaces = snapshot.spaces
        return true
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let provider = self.currentProviderState().provider
            provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
            self.requestRefresh(reason: .focusSpace)

            if needWindowFocus {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + 0.2
                ) { [weak self] in
                    self?.requestRefresh(reason: .focusSpaceWindow)
                }
            }
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let provider = self.currentProviderState().provider
            provider?.focusWindow(windowId: String(window.id))
            self.requestRefresh(reason: .focusWindow)
        }
    }

    private func handleApplicationLifecycleNotification(
        _ notification: Notification
    ) {
        guard
            let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
            let changedKind = ProviderKind(application: application)
        else {
            return
        }

        let shouldRestartCurrentProvider =
            currentProviderState().kind == changedKind
        updateProviderSelection(
            reason: .providerLifecycle,
            forceRestartCurrentProvider: shouldRestartCurrentProvider)
    }

    private func updateProviderSelection(
        reason: SpacesChangeReason,
        forceRestartCurrentProvider: Bool = false
    ) {
        let selectedKind = preferredRunningProviderKind()
        let currentState = currentProviderState()
        guard forceRestartCurrentProvider
            || selectedKind != currentState.kind
        else {
            if reason == .initial {
                requestRefresh(reason: reason)
            }
            return
        }

        let newProvider: AnySpacesProvider?
        switch selectedKind {
        case .yabai:
            newProvider = AnySpacesProvider(YabaiSpacesProvider())
        case .aerospace:
            newProvider = AnySpacesProvider(AerospaceSpacesProvider())
        case nil:
            newProvider = nil
        }

        let providerTransition = replaceProviderState(
            provider: newProvider, kind: selectedKind)
        let newProviderGeneration = providerTransition.generation
        providerTransition.oldProvider?.stopMonitoring()

        newProvider?.startMonitoring { [weak self] changeReason in
            guard let self,
                self.isCurrentProviderGeneration(
                    newProviderGeneration)
            else {
                return
            }
            self.requestRefresh(reason: changeReason)
        }

        requestRefresh(reason: reason)
    }

    private func preferredRunningProviderKind() -> ProviderKind? {
        var hasAerospace = false
        for application in NSWorkspace.shared.runningApplications {
            switch ProviderKind(application: application) {
            case .yabai:
                return .yabai
            case .aerospace:
                hasAerospace = true
            case nil:
                continue
            }
        }
        return hasAerospace ? .aerospace : nil
    }

    private func currentProviderState() -> (
        provider: AnySpacesProvider?,
        kind: ProviderKind?,
        generation: Int
    ) {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return (provider, providerKind, providerGeneration)
    }

    private func replaceProviderState(
        provider: AnySpacesProvider?, kind: ProviderKind?
    ) -> (oldProvider: AnySpacesProvider?, generation: Int) {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }

        let oldProvider = self.provider
        providerGeneration += 1
        self.provider = provider
        providerKind = kind
        return (oldProvider, providerGeneration)
    }

    private func isCurrentProviderGeneration(_ generation: Int) -> Bool {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return generation == providerGeneration
    }
}
