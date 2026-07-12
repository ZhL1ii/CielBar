import Foundation

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider,
    SpacesEventMonitoring
{
    typealias SpaceType = AeroSpace
    let executablePath = ConfigManager.shared.config.aerospace.path
    private var eventMonitor: AerospaceEventMonitor?
    private var supportsWorkspaceFocusMetadata: Bool?
    private var supportsWindowAppIdentityMetadata: Bool?

    deinit {
        stopMonitoring()
    }

    func startMonitoring(
        onChange: @escaping (SpacesProviderChange) -> Void
    ) {
        if eventMonitor == nil {
            eventMonitor = AerospaceEventMonitor(
                executablePath: executablePath)
        }
        eventMonitor?.startMonitoring(onChange: onChange)
    }

    func stopMonitoring() {
        eventMonitor?.stopMonitoring()
    }

    func getSpacesWithWindows() -> [AeroSpace]? {
        guard
            let spacesSnapshot = fetchSpaces(),
            let windows = fetchWindows()
        else {
            return nil
        }
        let spaces = spacesSnapshot.spaces
        let focusedSpaceId = spacesSnapshot.focusedSpaceId
        let focusedWindow = fetchFocusedWindow()
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in windows {
            var mutableWindow = window
            if let focused = focusedWindow, window.id == focused.id {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let focusedSpaceId {
                if var space = spaceDict[focusedSpaceId] {
                    space.windows.append(mutableWindow)
                    spaceDict[focusedSpaceId] = space
                }
            }
        }
        var resultSpaces = Array(spaceDict.values)
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.id < $1.id }
        }
        return resultSpaces.filter { !$0.windows.isEmpty }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) {
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            print("Aerospace error: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private func fetchSpaces() -> (
        spaces: [AeroSpace], focusedSpaceId: String?
    )? {
        var spaces: [AeroSpace]?
        if supportsWorkspaceFocusMetadata != false {
            spaces = fetchSpaces(arguments: [
                "list-workspaces", "--all", "--json", "--format",
                "%{workspace} %{workspace-is-focused}",
            ])
            if let spaces, spaces.allSatisfy({ $0.hasFocusMetadata }) {
                supportsWorkspaceFocusMetadata = true
                return (
                    spaces,
                    spaces.first(where: { $0.isFocused })?.id
                )
            }
            supportsWorkspaceFocusMetadata = false
        }

        if spaces == nil {
            spaces = fetchSpaces(arguments: [
                "list-workspaces", "--all", "--json",
            ])
        }
        guard var spaces else {
            return nil
        }
        let focusedSpaceId = fetchFocusedSpace()?.id
        for i in 0..<spaces.count {
            spaces[i].isFocused = (spaces[i].id == focusedSpaceId)
        }
        return (spaces, focusedSpaceId)
    }

    private func fetchSpaces(arguments: [String]) -> [AeroSpace]? {
        guard
            let data = runAerospaceCommand(arguments: arguments)
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data)
        } catch {
            print("Decode spaces error: \(error)")
            return nil
        }
    }

    private func fetchWindows() -> [AeroWindow]? {
        if supportsWindowAppIdentityMetadata != false {
            let windows = fetchWindows(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{app-bundle-id} "
                    + "%{app-bundle-path} %{app-pid} %{window-title} "
                    + "%{workspace}",
            ])
            if let windows {
                supportsWindowAppIdentityMetadata = true
                return windows
            }
            supportsWindowAppIdentityMetadata = false
        }

        return fetchWindows(arguments: [
            "list-windows", "--all", "--json", "--format",
            "%{window-id} %{app-name} %{window-title} %{workspace}",
        ])
    }

    private func fetchWindows(arguments: [String]) -> [AeroWindow]? {
        guard let data = runAerospaceCommand(arguments: arguments) else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data)
        } catch {
            print("Decode windows error: \(error)")
            return nil
        }
    }

    private func fetchFocusedSpace() -> AeroSpace? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data).first
        } catch {
            print("Decode focused space error: \(error)")
            return nil
        }
    }

    private func fetchFocusedWindow() -> AeroWindow? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data).first
        } catch {
            print("Decode focused window error: \(error)")
            return nil
        }
    }
}
