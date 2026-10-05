# CielBar

[English](README.md) | 简体中文

<p align="center" dir="auto">
  <p align="center" dir="auto">
    <a href="LICENSE">
      <img alt="License Badge" src="https://img.shields.io/badge/license-MIT-green.svg" style="max-width: 100%;">
    </a>
    <a href="https://github.com/ZhL1ii/cielbar/issues">
      <img alt="Issues Badge" src="https://img.shields.io/badge/issues-welcome-green.svg" style="max-width: 100%;">
    </a>
  </p>
</p>

**CielBar** 是一款轻量的 macOS 菜单栏替代工具，面向使用 [yabai](https://github.com/koekeishiya/yabai) 和 [AeroSpace](https://github.com/nikitabobko/AeroSpace) 等平铺式窗口管理器的用户。它最初 fork 自 [barik](https://github.com/mocki-toki/barik)，并在此基础上持续完善。

CielBar 将 Spaces、窗口、媒体播放、网络、电池、日历、番茄钟和时间信息集中到一个紧凑且可配置的面板中。

与 barik 相比，CielBar 目前主要有以下改进：

- Spaces 更新现在通过 yabai signal 和 AeroSpace `subscribe` 通知驱动，而不是依赖高频轮询。这降低了电量和资源消耗，同时保留了用于处理遗漏事件的备用刷新路径。
- 新增番茄钟组件。

## 截图

![浅色主题截图](resources/cielbar-light.png)

## 功能

- 通过 yabai 或 AeroSpace 显示 Spaces 和打开的窗口
- 点击 Space 切换到对应空间，点击窗口将其聚焦
- 支持 Spotify 和 Apple Music 的 Now Playing 控制
- 提供网络状态、电池、时间和日历事件组件
- 可选的番茄钟组件
- 可配置组件顺序、主题、弹出窗口、间距和外观
- 自动重新加载配置，并显示更新通知

## 系统要求

- macOS 14.6 或更高版本
- 只有在使用 Spaces 和窗口组件时，才需要安装 yabai 或 AeroSpace

## 安装

1. 从 [Releases](https://github.com/ZhL1ii/cielbar/releases) 下载最新版本。
2. 解压后，将 `CielBar.app` 移动到 Applications 文件夹。
3. 如果使用 Spaces 组件，请安装并配置 [yabai](https://github.com/koekeishiya/yabai) 或 [AeroSpace](https://github.com/nikitabobko/AeroSpace)。示例 [`.yabairc`](example/.yabairc) 包含适用于 CielBar 的顶部留白配置。
4. 在系统设置中隐藏 macOS 系统菜单栏，然后启动 CielBar。
5. 如果希望 CielBar 自动启动，请将它加入登录项。

## 配置

首次启动时，CielBar 会创建以下配置文件：

```text
~/.cielbar-config.toml
```

CielBar 也支持 XDG 风格的路径 `~/.config/cielbar/config.toml`。如果 CielBar 尚未创建自己的配置文件，但发现了旧版 barik 配置，它会将该配置导入主配置路径一次。

[默认配置](example/config.toml)中包含完整的默认 TOML 文件。CielBar 运行时会自动重新加载配置变更。

番茄钟组件默认不会启用。如需使用，请将 `"default.pomodoro"` 添加到 `widgets.displayed` 中。

可在计时器弹窗中以 `MM:SS` 格式设置时间，最长 `99:59`。点击时间可直接输入，也可以使用 ↑ / ↓ 调整。设置会一直保留。

## 注意事项

CielBar 替代的是菜单栏的视觉显示，目前不提供 File、Edit、View 等应用菜单项。如果需要这些菜单，请保留 macOS 系统菜单栏。

## 参与贡献

欢迎提交 issue 和 pull request。问题、错误报告和功能建议请使用 [issue tracker](https://github.com/ZhL1ii/cielbar/issues)。

## 许可证

CielBar 使用 [MIT License](LICENSE) 授权。它是 [barik](https://github.com/mocki-toki/barik) 的独立 fork，原项目的 MIT 版权声明保留在许可证文件中。

Apple 和 macOS 是 Apple Inc. 的商标。CielBar 与 Apple Inc. 没有关联，也未获得其认可或支持。
