@testable import CielBar
import XCTest

final class YabaiSpacesProviderTests: XCTestCase {
    func testBuildSpacesAppliesWindowDisplayPolicy() throws {
        let decoder = JSONDecoder()
        let spaces = try decoder.decode(
            [YabaiSpace].self,
            from: Data(
                #"""
                [
                  {"index": 1, "has-focus": true},
                  {"index": 2, "has-focus": false}
                ]
                """#.utf8
            )
        )
        let windows = try decoder.decode(
            [YabaiWindow].self,
            from: Data(
                #"""
                [
                  {
                    "id": 1001, "pid": 7001, "app": "Terminal",
                    "title": "", "space": 1, "has-focus": true,
                    "stack-index": 1, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "has-ax-reference": true, "is-visible": true,
                    "is-minimized": false, "is-hidden": false,
                    "is-floating": false, "is-sticky": false
                  },
                  {
                    "id": 1002, "pid": 7001, "app": "Terminal",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 2, "role": "", "subrole": "",
                    "root-window": true, "has-ax-reference": false,
                    "is-visible": false, "is-minimized": false,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": false
                  },
                  {
                    "id": 1003, "pid": 7002, "app": "Helper",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 3, "role": "", "subrole": "",
                    "root-window": true, "is-visible": false,
                    "is-minimized": false,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": false
                  },
                  {
                    "id": 1004, "pid": 7004, "app": "FloatingTool",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 4, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "is-visible": true, "is-minimized": false,
                    "is-hidden": false, "is-floating": true,
                    "is-sticky": false
                  },
                  {
                    "id": 1005, "pid": 7005, "app": "HiddenApp",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 5, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "is-visible": false, "is-minimized": false,
                    "is-hidden": true, "is-floating": false,
                    "is-sticky": false
                  },
                  {
                    "id": 1006, "pid": 7006, "app": "MinimizedApp",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 6, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "is-visible": false, "is-minimized": true,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": false
                  },
                  {
                    "id": 1007, "pid": 7007, "app": "StickyApp",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 7, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "is-visible": true, "is-minimized": false,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": true
                  },
                  {
                    "id": 1008, "pid": 7008, "app": "DialogApp",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 8, "role": "AXWindow",
                    "subrole": "AXDialog", "root-window": true,
                    "has-ax-reference": true, "is-visible": true,
                    "is-minimized": false, "is-hidden": false,
                    "is-floating": false, "is-sticky": false
                  },
                  {
                    "id": 1009, "pid": 7009, "app": "LegacyGhost",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 9, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "has-ax-reference": false, "is-visible": false,
                    "is-minimized": false, "is-hidden": false,
                    "is-floating": false, "is-sticky": false
                  },
                  {
                    "id": 1010, "pid": 7010, "app": "InvalidRole",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 10, "role": "AXButton",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "is-visible": true, "is-minimized": false,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": false
                  },
                  {
                    "id": 1011, "pid": 7011, "app": "InvalidSubrole",
                    "title": "", "space": 1, "has-focus": false,
                    "stack-index": 11, "role": "AXWindow",
                    "subrole": "AXSheet", "root-window": true,
                    "is-visible": true, "is-minimized": false,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": false
                  },
                  {
                    "id": 2001, "pid": 7003, "app": "Browser",
                    "title": "", "space": 2, "has-focus": false,
                    "stack-index": 1, "role": "AXWindow",
                    "subrole": "AXStandardWindow", "root-window": true,
                    "is-visible": false, "is-minimized": false,
                    "is-hidden": false, "is-floating": false,
                    "is-sticky": false
                  }
                ]
                """#.utf8
            )
        )

        let result = YabaiSpacesProvider.buildSpaces(
            spaces: spaces, windows: windows
        )
        let windowIDsBySpace = Dictionary(
            uniqueKeysWithValues: result.map {
                ($0.id, $0.windows.map(\.id))
            }
        )

        XCTAssertEqual(windowIDsBySpace[1], [1001, 1004, 1008])
        XCTAssertEqual(windowIDsBySpace[2], [2001])
    }
}
