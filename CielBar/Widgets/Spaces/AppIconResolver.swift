import AppKit
import Foundation

final class AppIconResolver {
    static let shared = AppIconResolver()

    private let cache = NSCache<NSString, NSImage>()
    private let cacheLock = NSLock()
    private var missedKeys: Set<String> = []
    private var lifecycleObservers: [NSObjectProtocol] = []

    private init() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for notificationName in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            lifecycleObservers.append(
                notificationCenter.addObserver(
                    forName: notificationName,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    self?.clearCache()
                })
        }
    }

    deinit {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in lifecycleObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    func icon(
        bundleIdentifier: String?,
        bundlePath: String?,
        processIdentifier: Int?,
        appName: String?
    ) -> NSImage? {
        if let bundleIdentifier = nonempty(bundleIdentifier),
            let icon = cachedIcon(
                forKey: "bundle-id:\(bundleIdentifier)",
                resolver: { [self] in
                    icon(forBundleIdentifier: bundleIdentifier)
                })
        {
            return icon
        }

        if let bundlePath = nonempty(bundlePath) {
            let standardizedPath = (bundlePath as NSString).standardizingPath
            if let icon = cachedIcon(
                forKey: "bundle-path:\(standardizedPath)",
                resolver: { [self] in icon(forBundlePath: standardizedPath) })
            {
                return icon
            }
        }

        if let processIdentifier,
            let icon = cachedIcon(
                forKey: "pid:\(processIdentifier)",
                resolver: { [self] in
                    icon(forProcessIdentifier: processIdentifier)
                })
        {
            return icon
        }

        if let appName = nonempty(appName),
            let icon = cachedIcon(
                forKey: "name:\(appName)",
                resolver: { [self] in icon(forAppName: appName) })
        {
            return icon
        }

        return nil
    }

    private func cachedIcon(
        forKey cacheKey: String, resolver: () -> NSImage?
    ) -> NSImage? {
        cacheLock.lock()
        if let cachedIcon = cache.object(forKey: cacheKey as NSString) {
            cacheLock.unlock()
            return cachedIcon
        }
        let isKnownMiss = missedKeys.contains(cacheKey)
        cacheLock.unlock()
        if isKnownMiss {
            return nil
        }

        let icon = resolver()

        cacheLock.lock()
        if let icon {
            cache.setObject(icon, forKey: cacheKey as NSString)
        } else {
            missedKeys.insert(cacheKey)
        }
        cacheLock.unlock()
        return icon
    }

    private func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage?
    {
        let workspace = NSWorkspace.shared
        if let application = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }), let icon = icon(for: application, workspace: workspace) {
            return icon
        }
        if let bundleURL = workspace.urlForApplication(
            withBundleIdentifier: bundleIdentifier)
        {
            return workspace.icon(forFile: bundleURL.path)
        }
        return nil
    }

    private func icon(forBundlePath bundlePath: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundlePath)
    }

    private func icon(forProcessIdentifier processIdentifier: Int) -> NSImage?
    {
        guard
            let application = NSRunningApplication(
                processIdentifier: pid_t(processIdentifier))
        else {
            return nil
        }
        return icon(for: application, workspace: NSWorkspace.shared)
    }

    private func icon(forAppName appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        guard
            let application = workspace.runningApplications.first(where: {
                $0.localizedName == appName
            })
        else {
            return nil
        }
        return icon(for: application, workspace: workspace)
    }

    private func clearCache() {
        cacheLock.lock()
        cache.removeAllObjects()
        missedKeys.removeAll()
        cacheLock.unlock()
    }

    private func icon(
        for application: NSRunningApplication, workspace: NSWorkspace
    ) -> NSImage? {
        if let bundleURL = application.bundleURL {
            return workspace.icon(forFile: bundleURL.path)
        }
        return application.icon
    }

    private func nonempty(_ value: String?) -> String? {
        guard
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
