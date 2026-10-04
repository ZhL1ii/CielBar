@testable import CielBar
import XCTest

final class YabaiSpacesProviderTests: XCTestCase {
    func testBuildSpacesHandlesTransientWindows() throws {
        let decoder = JSONDecoder()
        let spaces = try decoder.decode(
            [YabaiSpace].self,
            from: Data(#"[{"index": 3, "has-focus": true}]"#.utf8)
        )
        let cases = [
            ("Input source switch", 3, false, 10, 1),
            ("WeChat emoji picker", 0, true, 10, 2),
            ("WeChat quit prompt", 8, false, 10, 1),
            // A separate process keeps dialog merging from masking level filtering.
            ("Prism tooltip", 1000, false, 11, 1),
            ("Popup menu", 101, false, 11, 1),
            ("Help popup", 200, false, 11, 1),
        ]

        for (name, level, dialogFocused, dialogPID, expectedID) in cases {
            let windows = try decoder.decode(
                [YabaiWindow].self,
                from: Data(
                    """
                    [
                      {"id": 2, "pid": \(dialogPID), "space": 3, "stack-index": 1,
                       "role": "AXWindow", "subrole": "AXDialog", "root-window": true,
                       "level": \(level), "can-resize": false, "has-focus": \(dialogFocused),
                       "is-hidden": false, "is-floating": true, "is-sticky": false},
                      {"id": 1, "pid": 10, "space": 3, "stack-index": 1,
                       "role": "AXWindow", "subrole": "AXStandardWindow", "level": 0,
                       "has-focus": \(!dialogFocused),
                       "is-hidden": false, "is-floating": false, "is-sticky": false},
                      {"id": 3, "pid": 20, "space": 3, "stack-index": 2,
                       "role": "AXWindow", "subrole": "AXStandardWindow", "level": 3,
                       "has-focus": false, "is-hidden": false,
                       "is-floating": true, "is-sticky": false},
                      {"id": 4, "pid": 30, "space": 3, "stack-index": 3,
                       "role": "AXWindow", "subrole": "AXDialog", "level": 8,
                       "can-resize": false, "has-focus": false,
                       "is-hidden": false, "is-floating": true, "is-sticky": false},
                      {"id": 5, "pid": 40, "space": 3, "stack-index": 4,
                       "role": "AXWindow", "subrole": "AXStandardWindow",
                       "has-focus": false, "is-hidden": false,
                       "is-floating": false, "is-sticky": false},
                      {"id": 6, "pid": 40, "space": 3, "stack-index": 5,
                       "role": "AXWindow", "subrole": "AXStandardWindow",
                       "has-focus": false, "is-hidden": false,
                       "is-floating": false, "is-sticky": false},
                      {"id": 7, "pid": 40, "space": 3, "stack-index": 6,
                       "role": "AXWindow", "subrole": "AXDialog",
                       "can-resize": false, "has-focus": false,
                       "is-hidden": false, "is-floating": true, "is-sticky": false}
                    ]
                    """.utf8
                )
            )
            let result = YabaiSpacesProvider.buildSpaces(spaces: spaces, windows: windows)
            let displayedWindows = try XCTUnwrap(result.first?.windows, name)

            XCTAssertEqual(displayedWindows.map(\.id), [expectedID, 3, 4, 5, 6, 7], name)
            XCTAssertEqual(displayedWindows.filter(\.isFocused).map(\.id), [expectedID], name)
        }
    }

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
