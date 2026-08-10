# CielBar

## Project

CielBar is a native macOS menu bar replacement built with Swift, SwiftUI, and AppKit. It supports macOS 14.6 and later.

## Build and test

Use Xcode to run and debug `CielBar.xcodeproj`.

Must: before finishing a code change, run:

```sh
xcodebuild test -project "CielBar.xcodeproj" -scheme "CielBar" -configuration Debug -destination "platform=macOS"
```

## Architecture

`CielBarApp.swift` is the SwiftUI entry point. `AppDelegate.swift` manages the AppKit panels and app launch.

`MenuBarView.swift` maps configured widget IDs to views. Add a branch there when adding a configurable widget.

Keep each widget under `CielBar/Widgets/<Feature>/`. A widget may have a view, a manager or view model, and a popup.

`ConfigManager` is the only layer that reads, creates, migrates, and watches the TOML configuration. Widgets receive their settings through `ConfigProvider`.

Spaces uses provider protocols to isolate yabai and AeroSpace. Keep provider-specific commands and decoding in the provider, not in SwiftUI views.

## Implementation rules

Must: keep blocking I/O off the main queue. Publish changes to observable UI state on the main queue.

Must: protect mutable state shared by callbacks or background work. Follow the existing serial-queue or lock-based pattern in the feature you change.

Must: stop timers, observers, processes, and monitors when their owner is released or replaced.

Should: use `struct` for SwiftUI views and `final class` for stateful managers or view models.

Should: use `@StateObject` for objects a view owns and `@EnvironmentObject` for widget configuration supplied by its parent.

Should: capture `self` weakly in long-lived closures.

## Testing

Tests live in `CielBarTests/` and use XCTest with `@testable import CielBar`.

Must: add a focused regression test when changing Spaces window filtering, sorting, aggregation, or focus behavior.

Should: test provider data transformations with inline JSON fixtures. Do not require yabai or AeroSpace to be installed for unit tests.

## Configuration and compatibility

User configuration is stored outside the repository. The primary path is `~/.cielbar-config.toml`; `~/.config/cielbar/config.toml` is also supported.

Must: preserve existing configuration keys and defaults. Do not rename or remove a key without a migration path.

Must: retain the one-time import from legacy barik configuration unless a replacement migration is provided.

When configuration behavior changes, update the default TOML in `ConfigManager` and the configuration example in `README.md`.

## Avoid

Do not edit `CielBar.xcodeproj/project.pbxproj` to add ordinary Swift source files. The `CielBar` and `CielBarTests` folders are file-system-synchronized Xcode groups.

Do not add build, lint, or formatting commands that are not configured in this repository.

Do not read the TOML file directly from a widget or call yabai or AeroSpace directly from a SwiftUI view.

Do not remove the fallback refresh path for Spaces without preserving a recovery path for missed provider events.
