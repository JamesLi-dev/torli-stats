# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:c86a9c33127b -->
### 2026-08-28

### English

- Adds configurable animated status-bar runner logos and makes the Codex dashboard more compact by default.

- Status-bar Logo
  - Adds `StatusBarRunner` with 9 choices: RunCat, Beagle, Chicken, Dinosaur, Fishman, Frog, Horse, Rabbit, and Rubber Duck.
  - Adds `showStatusBarLogo`, `statusBarLogoAnimation`, and `statusBarRunner` settings, persisted through `UserDefaults` with defaults of enabled, enabled, and `.runCat`.
  - Adds `StatusBarLogoAnimator`, which slices bundled sprite sheets into macOS template images sized to a 20-point artwork height.
  - Animated playback follows a 2 fps baseline and scales from 1x through 20x using CPU usage; animation is disabled when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is enabled.
  - Settings now expose logo visibility, runner selection, and the “随 CPU 加速” option. The menu-bar metrics ordering remains configurable.
  - `AppDelegate` refreshes animation speed with metric updates and recreates the logo when relevant settings change.
  - Missing `UserDefaults` keys use documented defaults; `resetToDefaults()` clears the logo settings and restores the default configuration.

- Codex Dashboard
  - Shows at most 2 dashboard-visible Codex accounts initially; additional accounts can be expanded with “显示其余 \(n\) 个账号” and collapsed again.
  - Popover sizing now receives the number of currently displayed accounts so expansion and collapse can adjust the fitted height.
  - Primary remaining quota and its progress bar now use threshold colors: green above 50%, orange from 20% through 50%, and red below 20%.
  - Updates `TODO.md` to mark the account limit, quota warning colors, and status-bar Logo work as completed.

- Packaging and licensing
  - Adds 9 `Resources/runner-*.png` sprite sheets and packages them into the app bundle through `build-app.sh`.
  - Packages `THIRD_PARTY_NOTICES.md` and `LICENSES/Apache-2.0.txt` under the app’s `Contents/Resources` directory.
  - Documents the RunCatNeo / RunnerGallery artwork attribution, Apache License, Version 2.0, source projects, and the fact that the sprite sheets are rendered as macOS menu-bar template images and otherwise unmodified.
  - The build remains macOS-specific and continues to use `swift build`, `codesign`, and optional installation controlled by `SKIP_INSTALL=1`.

### 中文

- 新增可配置的状态栏动态 Logo，并让 Codex 面板默认以更紧凑的方式展示账号。

- 状态栏 Logo
  - 新增 `StatusBarRunner`，提供 9 种选择：RunCat、Beagle、Chicken、Dinosaur、Fishman、Frog、Horse、Rabbit 和 Rubber Duck。
  - 新增 `showStatusBarLogo`、`statusBarLogoAnimation` 和 `statusBarRunner` 设置，并通过 `UserDefaults` 持久化；默认值分别为启用、启用和 `.runCat`。
  - 新增 `StatusBarLogoAnimator`，将内置精灵图切分为 macOS template images，并将动画内容高度设为 20 point。
  - 动画以 2 fps 为基准，并根据 CPU 使用率在 1x 到 20x 之间调整播放速度；当 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` 启用时自动停止动画。
  - 设置页面新增 Logo 显示、动画角色和“随 CPU 加速”选项；菜单栏指标顺序仍可配置。
  - `AppDelegate` 会在指标更新时调整动画速度，并在相关设置改变时重新创建 Logo。
  - 缺少新的 `UserDefaults` key 时使用上述默认值；`resetToDefaults()` 会清理 Logo 设置并恢复默认配置。

- Codex 面板
  - Codex 面板默认最多展示前 2 个可见账号；其余账号可通过“显示其余 \(n\) 个账号”展开，也可以再次收起。
  - Popover 高度现在会接收当前实际展示的账号数量，因此展开和收起账号时会重新计算适配高度。
  - 主额度的剩余比例及进度条改为按阈值显示颜色：高于 50% 为绿色，20% 至 50% 为橙色，低于 20% 为红色。
  - `TODO.md` 已将账号数量限制、额度告警颜色和状态栏 Logo 工作标记为完成。

- 打包与许可证
  - 新增 9 个 `Resources/runner-*.png` 精灵图，并通过 `build-app.sh` 打包到 App bundle。
  - 将 `THIRD_PARTY_NOTICES.md` 和 `LICENSES/Apache-2.0.txt` 打包到 App 的 `Contents/Resources` 目录。
  - 补充 RunCatNeo / RunnerGallery artwork 归属、Apache License, Version 2.0、来源项目，以及精灵图会被渲染为 macOS 菜单栏 template images 且未作其他修改的说明。
  - 构建仍限定于 macOS，并继续使用 `swift build`、`codesign`；是否安装到系统由 `SKIP_INSTALL=1` 控制。
