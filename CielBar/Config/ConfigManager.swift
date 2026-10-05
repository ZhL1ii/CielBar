import Foundation
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config = Config()
    @Published private(set) var initError: String?
    
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var configFilePath: String?

    private init() {
        loadOrCreateConfigIfNeeded()
    }

    private func loadOrCreateConfigIfNeeded() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let primaryPath = "\(homePath)/.cielbar-config.toml"
        let xdgPath = "\(homePath)/.config/cielbar/config.toml"
        let legacyPaths = [
            "\(homePath)/.barik-config.toml",
            "\(homePath)/.config/barik/config.toml"
        ]
        var chosenPath: String?

        if FileManager.default.fileExists(atPath: primaryPath) {
            chosenPath = primaryPath
        } else if FileManager.default.fileExists(atPath: xdgPath) {
            chosenPath = xdgPath
        } else if let legacyPath = legacyPaths.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) {
            do {
                try copyConfig(from: legacyPath, to: primaryPath)
                chosenPath = primaryPath
            } catch {
                initError = "Error importing legacy config: \(error.localizedDescription)"
                print("Error when importing legacy config:", error)
                return
            }
        } else {
            do {
                try createDefaultConfig(at: primaryPath)
                chosenPath = primaryPath
            } catch {
                initError = "Error creating default config: \(error.localizedDescription)"
                print("Error when creating default config:", error)
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            parseConfigFile(at: path)
            startWatchingFile(at: path)
        }
    }

    private func copyConfig(from sourcePath: String, to destinationPath: String) throws {
        let destinationURL = URL(fileURLWithPath: destinationPath)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil)
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    private func parseConfigFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            DispatchQueue.main.async {
                self.config = Config(rootToml: rootToml)
            }
        } catch {
            initError = "Error parsing TOML file: \(error.localizedDescription)"
            print("Error when parsing TOML file:", error)
        }
    }

    private func createDefaultConfig(at path: String) throws {
        let defaultTOML = """
            # If you installed yabai or aerospace without using Homebrew,
            # manually set the path to the binary. For example:
            #
            # yabai.path = "/run/current-system/sw/bin/yabai"
            # aerospace.path = ...
            
            theme = "system" # system, light, dark

            [widgets]
            displayed = [ # widgets on menu bar
                "default.spaces",
                "spacer",
                "default.network",
                "default.battery",
                "divider",
                # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
                "default.time"
            ]

            [widgets.default.spaces]
            space.show-key = true        # show space number (or character, if you use AeroSpace)
            window.show-title = true
            window.title.max-length = 50

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.time]
            format = "E d, J:mm"
            calendar.format = "J:mm"

            calendar.show-events = true
            # calendar.allow-list = ["Home", "Personal"] # show only these calendars
            # calendar.deny-list = ["Work", "Boss"] # show all calendars except these

            [widgets.default.time.popup]
            view-variant = "box"

            # Pomodoro durations are set in its popup and saved separately, not in TOML.
            
            ### EXPERIMENTAL, WILL BE REPLACED BY STYLE API IN THE FUTURE
            [experimental.background]
            displayed = false
            height = "menu-bar"
            blur = 3

            [experimental.foreground]
            height = "menu-bar"
            horizontal-padding = 25
            spacing = 15

            [experimental.foreground.widgets-background]
            displayed = false
            blur = 3
            """
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func startWatchingFile(at path: String) {
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }
        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: .write,
            queue: DispatchQueue.global())
        fileWatchSource?.setEventHandler { [weak self] in
            guard let self = self, let path = self.configFilePath else {
                return
            }
            self.parseConfigFile(at: path)
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        fileWatchSource?.resume()
    }

    func updateConfigValue(key: String, newValue: String) {
        guard let path = configFilePath else {
            print("Config file path is not set")
            return
        }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLString(
                original: currentText, key: key, newValue: newValue)
            try updatedText.write(
                toFile: path, atomically: false, encoding: .utf8)
            DispatchQueue.main.async {
                self.parseConfigFile(at: path)
            }
        } catch {
            print("Error updating config:", error)
        }
    }

    private func updatedTOMLString(
        original: String, key: String, newValue: String
    ) -> String {
        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(actualKey) = \"\(newValue)\"")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \"\(newValue)\"")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \"\(newValue)\"")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        }
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
    }

    func resolvedWidgetConfig(for item: TomlWidgetItem) -> ConfigData {
        let global = globalWidgetConfig(for: item.id)
        if item.inlineParams.isEmpty {
            return global
        }
        var merged = global
        for (key, value) in item.inlineParams {
            merged[key] = value
        }
        return merged
    }
}
