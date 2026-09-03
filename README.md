# CielBar

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center" dir="auto">
  <img src="resources/header-image.png" alt="CielBar">
  <p align="center" dir="auto">
    <a href="LICENSE">
      <img alt="License Badge" src="https://img.shields.io/badge/license-MIT-green.svg" style="max-width: 100%;">
    </a>
    <a href="https://github.com/ZhL1ii/cielbar/issues">
      <img alt="Issues Badge" src="https://img.shields.io/badge/issues-welcome-green.svg" style="max-width: 100%;">
    </a>
  </p>
</p>

**CielBar** is a lightweight macOS menu bar replacement for users of tiling window managers such as [yabai](https://github.com/koekeishiya/yabai) and [AeroSpace](https://github.com/nikitabobko/AeroSpace). It started as a fork of [barik](https://github.com/mocki-toki/barik) and continues to build on it.

It puts spaces, windows, media, network, battery, calendar, Pomodoro, and time information in one compact, configurable panel.

The main differences from barik are:

- Spaces updates now use yabai signals and AeroSpace `subscribe` notifications instead of frequent polling. This reduces battery drain and resource use while keeping a fallback refresh path for missed events.
- CielBar adds a Pomodoro timer widget.

## Screenshots

- [Light theme screenshot](resources/cielbar-light.png)

## Features

- Spaces and open windows through yabai or AeroSpace
- Click a space to switch to it or a window to focus it
- Now Playing controls for Spotify and Apple Music
- Widgets for network status, battery, time, and calendar events
- An optional Pomodoro timer
- Customize widget order, themes, popups, spacing, and appearance
- Automatic configuration reloads and update notifications

## Requirements

- macOS 14.6 or later
- yabai or AeroSpace, if you want the Spaces and windows widget

## Installation

1. Download the latest build from [Releases](https://github.com/ZhL1ii/cielbar/releases).
2. Unzip it and move `CielBar.app` to your Applications folder.
3. If you use the Spaces widget, install and configure [yabai](https://github.com/koekeishiya/yabai) or [AeroSpace](https://github.com/nikitabobko/AeroSpace). The example [`.yabairc`](example/.yabairc) includes the top-padding setup for CielBar.
4. In System Settings, hide the macOS system menu bar, then launch CielBar.
5. Add CielBar to your login items if you want it to start automatically.

## Configuration

On first launch, CielBar creates this file:

```text
~/.cielbar-config.toml
```

The XDG-style path `~/.config/cielbar/config.toml` is also supported. If CielBar finds a legacy barik configuration before creating its own, it imports that file once into the primary CielBar path.

The [default configuration](example/config.toml) contains the complete default TOML file. CielBar reloads changes while it is running.

To use the Pomodoro widget, add `"default.pomodoro"` to `widgets.displayed`.

## Notes

CielBar replaces the visual menu bar, but it does not currently provide application menu items such as File, Edit, or View. If you need those menus, keep the macOS system menu bar available.

## Contributing

Issues and pull requests are welcome. Use the [issue tracker](https://github.com/ZhL1ii/cielbar/issues) for questions, bug reports, and feature requests.

## License

CielBar is available under the [MIT License](LICENSE). It is an independent fork of [barik](https://github.com/mocki-toki/barik), and the original MIT copyright notice remains in the license file.

Apple and macOS are trademarks of Apple Inc. CielBar is not affiliated with or endorsed by Apple Inc.
