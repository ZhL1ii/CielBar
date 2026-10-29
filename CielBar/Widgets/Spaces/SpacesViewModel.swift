import AppKit
import Combine
import Foundation

enum SpacesFocusCommand: Equatable {
    case space(String)
    case window(String)
}

final class SpacesFocusCoordinator {
    typealias CommandHandler = (SpacesFocusCommand) -> Bool
    typealias RefreshHandler = (SpacesChangeReason) -> Void
    typealias DelayedWorkScheduler = (DispatchWorkItem) -> Void

    private let commandHandler: CommandHandler
    private let refreshHandler: RefreshHandler
    private let coordinationQueue: DispatchQueue
    private let scheduleDelayedWork: DelayedWorkScheduler
    private var pendingWindowFocus: DispatchWorkItem?

    init(
        delay: TimeInterval = 0.1,
        coordinationQueue: DispatchQueue = DispatchQueue(
            label: "moe.ciel.CielBar.spaces-focus-coordinator",
            qos: .userInitiated),
        commandHandler: @escaping CommandHandler,
        refreshHandler: @escaping RefreshHandler,
        scheduleDelayedWork: DelayedWorkScheduler? = nil
    ) {
        self.commandHandler = commandHandler
        self.refreshHandler = refreshHandler
        self.coordinationQueue = coordinationQueue
        self.scheduleDelayedWork = scheduleDelayedWork ?? { workItem in
            coordinationQueue.asyncAfter(
                deadline: .now() + delay,
                execute: workItem)
        }
    }

    func cancelPendingFocus() {
        coordinationQueue.async { [weak self] in
            self?.pendingWindowFocus?.cancel()
            self?.pendingWindowFocus = nil
        }
    }

    func focusWindow(windowID: String, inSpaceWithID spaceID: String) {
        coordinationQueue.async { [weak self] in
            guard let self else { return }

            self.pendingWindowFocus?.cancel()
            self.pendingWindowFocus = nil

            if self.commandHandler(.space(spaceID)) {
                self.refreshHandler(.focusSpace)
            }

            let windowFocus = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingWindowFocus = nil
                if self.commandHandler(.window(windowID)) {
                    self.refreshHandler(.focusWindow)
                }
            }
            self.pendingWindowFocus = windowFocus
            self.scheduleDelayedWork(windowFocus)
        }
    }
}

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
    @Published private(set) var isReconnecting = false
    private let fallbackRefreshInterval: TimeInterval = 10
    private let providerStateLock = NSLock()
    private let monitoringQueue = DispatchQueue(label: "moe.ciel.CielBar.spaces-monitoring")
    private var provider: AnySpacesProvider?
    private var providerKind: ProviderKind?
    private var providerGeneration = 0
    private var connectionRevision = 0
    private var canSendCommands = false
    // Connection flags and retry scheduling below are confined to the main queue.
    private var eventsConnected = false
    private var snapshotRetry: DispatchWorkItem?
    private var snapshotRetryAttempt = 0
    private var fallbackRefreshTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var systemWakeObserver: NSObjectProtocol?
    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminationObserver: NSObjectProtocol?
    private var pendingFocusChange: SpacesFocusChange?
    private var focusCoordinator: SpacesFocusCoordinator?
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
            self?.checkConnection(reason: .fallbackPoll)
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkConnection(reason: .appActivated)
        }

        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkConnection(reason: .systemWake)
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
        snapshotRetry?.cancel()
        snapshotRetry = nil
        focusCoordinator?.cancelPendingFocus()
        monitoringQueue.async {
            currentProvider?.stopMonitoring()
        }

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

    func requestRefresh(
        reason: SpacesChangeReason,
        policy: SpacesRefreshPolicy = .debounced
    ) {
        refreshScheduler.requestRefresh(reason: reason, policy: policy)
    }

    private func checkConnection(reason: SpacesChangeReason) {
        if currentProviderState().provider == nil {
            updateProviderSelection(reason: reason)
        }
        currentProviderState().provider?.checkConnection()
        requestRefresh(reason: reason)
    }

    private func beginRecovery() {
        providerStateLock.lock()
        canSendCommands = false
        connectionRevision += 1
        providerStateLock.unlock()
        if !isReconnecting { print("Spaces: reconnecting") }
        isReconnecting = true
        pendingFocusChange = nil
        focusCoordinator?.cancelPendingFocus()
        focusCoordinator = nil
    }

    private func scheduleSnapshotRetry() {
        guard snapshotRetry == nil, currentProviderState().provider != nil else { return }
        let state = currentProviderState()
        let delay = min(pow(2, Double(snapshotRetryAttempt)), 10)
        snapshotRetryAttempt = min(snapshotRetryAttempt + 1, 4)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrentProviderGeneration(state.generation) else { return }
            self.snapshotRetry = nil
            self.currentProviderState().provider?.checkConnection()
            self.requestRefresh(reason: .providerConnection, policy: .immediate)
        }
        snapshotRetry = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func loadSpacesSnapshot() -> SpacesRefreshSnapshot? {
        let state = currentProviderState()
        guard let provider = state.provider else { return nil }
        guard let spaces = provider.getSpacesWithWindows() else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentConnection(state.generation, state.revision) else { return }
                if !self.isReconnecting { self.beginRecovery() }
                self.scheduleSnapshotRetry()
            }
            return nil
        }
        guard isCurrentConnection(state.generation, state.revision) else { return nil }
        return SpacesRefreshSnapshot(
            spaces: spaces.sorted { $0.id < $1.id },
            providerGeneration: state.generation,
            connectionRevision: state.revision)
    }

    private func publish(snapshot: SpacesRefreshSnapshot) -> Bool {
        guard isCurrentConnection(snapshot.providerGeneration, snapshot.connectionRevision),
            eventsConnected
        else {
            return false
        }
        snapshotRetry?.cancel()
        snapshotRetry = nil
        snapshotRetryAttempt = 0
        providerStateLock.lock()
        canSendCommands = true
        providerStateLock.unlock()
        if isReconnecting { print("Spaces: connection restored (\(snapshot.spaces.count) spaces)") }
        isReconnecting = false
        var spacesToPublish = snapshot.spaces
        if let pendingFocusChange {
            if snapshot.spaces.contains(where: {
                $0.id == pendingFocusChange.workspaceID
            }) && snapshot.spaces.allSatisfy({
                $0.matches(pendingFocusChange)
            }) {
                self.pendingFocusChange = nil
            } else {
                spacesToPublish = snapshot.spaces.map {
                    $0.applying(pendingFocusChange)
                }
            }
        }
        if spaces != spacesToPublish { spaces = spacesToPublish }
        return true
    }

    private func applyFocusChange(_ focusChange: SpacesFocusChange) {
        guard !isReconnecting else { return }
        if let pendingFocusChange,
            pendingFocusChange.workspaceID == focusChange.workspaceID,
            !focusChange.updatesWindowFocus
        {
            self.pendingFocusChange = pendingFocusChange
        } else {
            pendingFocusChange = focusChange
        }
        let updatedSpaces = spaces.map { $0.applying(focusChange) }
        if updatedSpaces != spaces { spaces = updatedSpaces }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        let state = currentProviderState()
        guard state.canSendCommands else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.canExecuteCommand(state.generation, state.revision),
                let provider = state.provider
            else { return }
            provider.focusSpace(spaceId: space.id, needWindowFocus: false)
            self.requestRefresh(reason: .focusSpace)

            // Keep yabai's existing fallback focus behavior, bound to this connection.
            if needWindowFocus, state.kind == .yabai {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.canExecuteCommand(state.generation, state.revision),
                        let spaces = provider.getSpacesWithWindows(),
                        let updatedSpace = spaces.first(where: { $0.id == space.id }),
                        !updatedSpace.windows.contains(where: \.isFocused),
                        let window = updatedSpace.windows.first,
                        self.canExecuteCommand(state.generation, state.revision)
                    else { return }
                    provider.focusWindow(windowId: String(window.id))
                    self.requestRefresh(reason: .focusSpaceWindow)
                }
            }
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        let state = currentProviderState()
        guard state.canSendCommands else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.canExecuteCommand(state.generation, state.revision) else { return }
            state.provider?.focusWindow(windowId: String(window.id))
            self.requestRefresh(reason: .focusWindow)
        }
    }

    func focusWindow(_ window: AnyWindow, in space: AnySpace) {
        let state = currentProviderState()
        guard state.canSendCommands, let provider = state.provider else { return }
        if focusCoordinator == nil {
            // Each coordinator belongs to one connection, including both delayed commands.
            focusCoordinator = SpacesFocusCoordinator(
                commandHandler: { [weak self] command in
                    guard let self, self.canExecuteCommand(state.generation, state.revision) else {
                        return false
                    }
                    switch command {
                    case .space(let spaceID):
                        provider.focusSpace(spaceId: spaceID, needWindowFocus: false)
                    case .window(let windowID):
                        provider.focusWindow(windowId: windowID)
                    }
                    return true
                },
                refreshHandler: { [weak self] reason in
                    self?.requestRefresh(reason: reason)
                })
        }
        focusCoordinator?.focusWindow(windowID: String(window.id), inSpaceWithID: space.id)
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
        let currentState = currentProviderState()
        let selectedKind = currentState.kind ?? preferredRunningProviderKind()
        guard forceRestartCurrentProvider
            || (currentState.provider == nil && selectedKind != nil)
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
        snapshotRetry?.cancel()
        snapshotRetry = nil
        snapshotRetryAttempt = 0
        eventsConnected = false
        beginRecovery()
        monitoringQueue.async {
            providerTransition.oldProvider?.stopMonitoring()
            // Stop the old monitor before registering a replacement with the same signal labels.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentProviderGeneration(newProviderGeneration) else { return }
                newProvider?.startMonitoring { [weak self] change in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isCurrentProviderGeneration(newProviderGeneration) else { return }
                        if let connectionState = change.connectionState {
                            self.eventsConnected = connectionState == .connected
                            if connectionState == .reconnecting { self.beginRecovery() }
                        }
                        if let focusChange = change.focusChange {
                            self.applyFocusChange(focusChange)
                        }
                        self.requestRefresh(reason: change.reason, policy: change.refreshPolicy)
                    }
                }
            }
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
        generation: Int,
        revision: Int,
        canSendCommands: Bool
    ) {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return (provider, providerKind, providerGeneration, connectionRevision, canSendCommands)
    }

    private func replaceProviderState(
        provider: AnySpacesProvider?, kind: ProviderKind?
    ) -> (oldProvider: AnySpacesProvider?, generation: Int) {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }

        let oldProvider = self.provider
        providerGeneration += 1
        canSendCommands = false
        self.provider = provider
        providerKind = kind
        return (oldProvider, providerGeneration)
    }

    private func isCurrentConnection(_ generation: Int, _ revision: Int) -> Bool {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return providerGeneration == generation && connectionRevision == revision
    }

    private func canExecuteCommand(_ generation: Int, _ revision: Int) -> Bool {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return canSendCommands && providerGeneration == generation && connectionRevision == revision
    }

    private func isCurrentProviderGeneration(_ generation: Int) -> Bool {
        providerStateLock.lock()
        defer { providerStateLock.unlock() }
        return generation == providerGeneration
    }
}
