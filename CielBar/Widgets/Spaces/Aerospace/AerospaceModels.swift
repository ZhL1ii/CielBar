import Foundation

struct AeroWindow: WindowModel {
    let id: Int
    let title: String
    let appName: String?
    let appBundleId: String?
    let appBundlePath: String?
    let appPid: Int?
    var isFocused: Bool = false
    let workspace: String?

    enum CodingKeys: String, CodingKey {
        case id = "window-id"
        case title = "window-title"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case appBundlePath = "app-bundle-path"
        case appPid = "app-pid"
        case workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleId = try container.decodeIfPresent(
            String.self, forKey: .appBundleId)
        appBundlePath = try container.decodeIfPresent(
            String.self, forKey: .appBundlePath)
        appPid = try container.decodeIfPresent(Int.self, forKey: .appPid)
        workspace = try container.decodeIfPresent(
            String.self, forKey: .workspace)
        isFocused = false
    }
}

struct AeroSpace: SpaceModel {
    typealias WindowType = AeroWindow
    let workspace: String
    var id: String { workspace }
    var isFocused: Bool = false
    var hasFocusMetadata: Bool = false
    var windows: [AeroWindow] = []

    enum CodingKeys: String, CodingKey {
        case workspace
        case isFocused = "workspace-is-focused"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try container.decode(String.self, forKey: .workspace)
        if let isFocused = try container.decodeIfPresent(
            Bool.self, forKey: .isFocused)
        {
            self.isFocused = isFocused
            hasFocusMetadata = true
        }
    }

    init(workspace: String, isFocused: Bool = false, windows: [AeroWindow] = [])
    {
        self.workspace = workspace
        self.isFocused = isFocused
        self.windows = windows
    }
}
