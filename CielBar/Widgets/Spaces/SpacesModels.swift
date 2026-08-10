import AppKit

protocol SpaceModel: Identifiable, Equatable, Codable {
    associatedtype WindowType: WindowModel
    var isFocused: Bool { get set }
    var windows: [WindowType] { get set }
}

protocol WindowModel: Identifiable, Equatable, Codable {
    var id: Int { get }
    var title: String { get }
    var appName: String? { get }
    var appBundleId: String? { get }
    var appBundlePath: String? { get }
    var appPid: Int? { get }
    var isFocused: Bool { get }
}

protocol SpacesProvider {
    associatedtype SpaceType: SpaceModel
    func getSpacesWithWindows() -> [SpaceType]?
}

enum SpacesRefreshPolicy: Equatable {
    case debounced
    case immediate
}

enum SpacesChangeReason: String {
    case initial
    case fallbackPoll = "fallback-poll"
    case appActivated = "app-activated"
    case systemWake = "system-wake"
    case providerEvent = "provider-event"
    case providerFocusEvent = "provider-focus-event"
    case focusSpace = "focus-space"
    case focusSpaceWindow = "focus-space-window"
    case focusWindow = "focus-window"
    case providerLifecycle = "provider-lifecycle"
}

struct SpacesFocusChange {
    let workspaceID: String
    let windowID: Int?
    let updatesWindowFocus: Bool
}

struct SpacesProviderChange {
    let reason: SpacesChangeReason
    let focusChange: SpacesFocusChange?
    let refreshPolicy: SpacesRefreshPolicy

    init(
        reason: SpacesChangeReason,
        focusChange: SpacesFocusChange? = nil,
        refreshPolicy: SpacesRefreshPolicy = .debounced
    ) {
        self.reason = reason
        self.focusChange = focusChange
        self.refreshPolicy = refreshPolicy
    }
}

protocol SpacesEventMonitoring {
    func startMonitoring(
        onChange: @escaping (SpacesProviderChange) -> Void)
    func stopMonitoring()
}

protocol SwitchableSpacesProvider: SpacesProvider {
    func focusSpace(spaceId: String, needWindowFocus: Bool)
    func focusWindow(windowId: String)
}

struct AnyWindow: Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String?
    let isFocused: Bool
    let appIcon: NSImage?

    init<W: WindowModel>(_ window: W) {
        self.id = window.id
        self.title = window.title
        self.appName = window.appName
        self.isFocused = window.isFocused
        self.appIcon = AppIconResolver.shared.icon(
            bundleIdentifier: window.appBundleId,
            bundlePath: window.appBundlePath,
            processIdentifier: window.appPid,
            appName: window.appName)
    }

    private init(
        id: Int,
        title: String,
        appName: String?,
        isFocused: Bool,
        appIcon: NSImage?
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.isFocused = isFocused
        self.appIcon = appIcon
    }

    func updatingFocus(_ isFocused: Bool) -> AnyWindow {
        AnyWindow(
            id: id,
            title: title,
            appName: appName,
            isFocused: isFocused,
            appIcon: appIcon)
    }

    static func == (lhs: AnyWindow, rhs: AnyWindow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.isFocused == rhs.isFocused
    }
}

struct AnySpace: Identifiable, Equatable {
    let id: String
    let isFocused: Bool
    let windows: [AnyWindow]

    init<S: SpaceModel>(_ space: S) {
        if let aero = space as? AeroSpace {
            self.id = aero.workspace
        } else if let yabai = space as? YabaiSpace {
            self.id = String(yabai.id)
        } else {
            self.id = "0"
        }
        self.isFocused = space.isFocused
        self.windows = space.windows.map { AnyWindow($0) }
    }

    private init(id: String, isFocused: Bool, windows: [AnyWindow]) {
        self.id = id
        self.isFocused = isFocused
        self.windows = windows
    }

    func applying(_ focusChange: SpacesFocusChange) -> AnySpace {
        let isTargetWorkspace = id == focusChange.workspaceID
        let updatedWindows = windows.map { window in
            if focusChange.updatesWindowFocus {
                return window.updatingFocus(
                    isTargetWorkspace && window.id == focusChange.windowID)
            }
            if !isTargetWorkspace {
                return window.updatingFocus(false)
            }
            return window
        }
        return AnySpace(
            id: id,
            isFocused: isTargetWorkspace,
            windows: updatedWindows)
    }

    func matches(_ focusChange: SpacesFocusChange) -> Bool {
        guard isFocused == (id == focusChange.workspaceID) else {
            return false
        }
        guard focusChange.updatesWindowFocus else { return true }

        return windows.allSatisfy { window in
            window.isFocused
                == (id == focusChange.workspaceID
                    && window.id == focusChange.windowID)
        }
    }

    static func == (lhs: AnySpace, rhs: AnySpace) -> Bool {
        return lhs.id == rhs.id && lhs.isFocused == rhs.isFocused
            && lhs.windows == rhs.windows
    }
}

class AnySpacesProvider {
    private let _getSpacesWithWindows: () -> [AnySpace]?
    private let _focusSpace: ((String, Bool) -> Void)?
    private let _focusWindow: ((String) -> Void)?
    private let _startMonitoring: (
        @escaping (SpacesProviderChange) -> Void
    ) -> Void
    private let _stopMonitoring: () -> Void

    init<P: SpacesProvider>(_ provider: P) {
        _getSpacesWithWindows = {
            provider.getSpacesWithWindows()?.map { AnySpace($0) }
        }
        if let switchable = provider as? any SwitchableSpacesProvider {
            _focusSpace = { spaceId, needWindowFocus in
                switchable.focusSpace(
                    spaceId: spaceId, needWindowFocus: needWindowFocus)
            }
            _focusWindow = { windowId in
                switchable.focusWindow(windowId: windowId)
            }
        } else {
            _focusSpace = nil
            _focusWindow = nil
        }

        if let eventMonitor = provider as? any SpacesEventMonitoring {
            _startMonitoring = { onChange in
                eventMonitor.startMonitoring(onChange: onChange)
            }
            _stopMonitoring = {
                eventMonitor.stopMonitoring()
            }
        } else {
            _startMonitoring = { _ in }
            _stopMonitoring = {}
        }
    }

    func getSpacesWithWindows() -> [AnySpace]? {
        _getSpacesWithWindows()
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _focusSpace?(spaceId, needWindowFocus)
    }

    func focusWindow(windowId: String) {
        _focusWindow?(windowId)
    }

    func startMonitoring(
        onChange: @escaping (SpacesProviderChange) -> Void
    ) {
        _startMonitoring(onChange)
    }

    func stopMonitoring() {
        _stopMonitoring()
    }
}
