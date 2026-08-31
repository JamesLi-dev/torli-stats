# Changelog

All notable changes to Torli Stats are documented here.

## [1.1.0] — 2026-08-31

<!-- ai-changelog:34a1a150dc45 -->
### 2026-08-31

### English

- Added Codex account management improvements, status-bar Logo reordering, refreshed settings UI, and compact Bluetooth battery indicators; bumped `CFBundleShortVersionString` to `1.1.0`.

- Codex usage and account management:
  - Added persisted `codexAutoRefresh` and `codexRefreshInterval` settings, with supported intervals of 1, 5, 10, and 30 minutes; reset-to-defaults restores automatic refresh every 5 minutes.
  - Propagated `CodexRefreshSettings` through `CodexAccountsUsageStore` into each `CodexUsageStore`, while creating usage stores only for accounts visible in the Dashboard or status bar.
  - Added per-account “测试连接” handling through `CodexAccountsUsageStore.testConnection(for:completion:)`, including `CodexUsageClient.validate(homePath:)` checks before fetching.
  - Added Codex Home validation status, resolved-path display, and last successful refresh timestamps to the settings view.
  - Added managed-account directory creation under `~/.torli-stats-codex` with POSIX permissions `0o700`. Existing account removal continues to remove only application configuration according to the settings text.
  - Increased the settings window and Codex account sheet layout to accommodate account status, refresh controls, and connection actions.
  - `CodexUsageClient.fetch` now uses the validation result when checking the Codex Home directory, `auth.json`, and the executable path.

- Status-bar display:
  - Added `StatusBarMetricGroup.logo`, allowing the Logo to participate in `statusBarMetricOrder` and be placed among system, network, and Codex groups.
  - Reworked status-bar composition to render the Logo and metric groups into one `NSImage`, preserving the selected order and applying the current `NSAppearance`.
  - The animated Logo now supplies updated images through a callback; Logo visibility, CPU-driven animation, and reduce-motion handling remain tied to `StatusBarLogoConfiguration`.
  - Replaced the privacy-mode menu checkmark state with SF Symbols, disabled the menu state column, and added symbols to the About, Settings, Refresh, Privacy, and Quit items.
  - Replaced manual up/down ordering buttons with drag-and-drop using `UTType.text`, while retaining “恢复默认顺序”.

- Settings organization:
  - Reorganized the settings window into two columns with grouped labels and subsections for appearance, status-bar content, system metric style, monitoring, sensors, and system options.
  - Added explicit field labels and adjusted minimum/ideal window sizing to support the expanded layout.

- Power panel:
  - When more than two Bluetooth devices are present, displays compact 48×48 battery rings with device-type icons and charge percentages instead of full `BatteryRing` rows.
  - Preserves device names through `.help` and accessibility labels, including privacy-mode names and unavailable battery values.

- Platform and packaging:
  - `Info.plist` continues to declare `LSMinimumSystemVersion` as macOS `13.0`.
  - The sensor-helper workflow continues to use administrator privileges where required by the existing installation flow.

### 中文

- 新增 Codex 账号管理改进、状态栏 Logo 排序、设置界面重组和紧凑型蓝牙电量显示；`CFBundleShortVersionString` 更新为 `1.1.0`。

- Codex 用量与账号管理：
  - 新增持久化设置 `codexAutoRefresh` 和 `codexRefreshInterval`，支持 1、5、10、30 分钟间隔；恢复默认设置后为启用自动刷新、每 5 分钟刷新。
  - 将 `CodexRefreshSettings` 从 `CodexAccountsUsageStore` 传递至各个 `CodexUsageStore`，并且只为显示在 Dashboard 或状态栏中的账号创建 usage store。
  - 新增基于 `CodexAccountsUsageStore.testConnection(for:completion:)` 的“测试连接”操作，在读取前通过 `CodexUsageClient.validate(homePath:)` 执行检查。
  - 在设置界面显示 Codex Home 校验状态、解析后的路径和每个账号上次成功刷新的时间。
  - 受管理账号创建在 `~/.torli-stats-codex` 下的独立目录，并设置 POSIX 权限 `0o700`。根据设置界面现有说明，移除账号仍只删除应用配置。
  - 扩大设置窗口和 Codex 账号弹窗布局，以容纳账号状态、刷新设置和连接操作。
  - `CodexUsageClient.fetch` 现在使用校验结果检查 Codex Home 目录、`auth.json` 和 executable path。

- 状态栏显示：
  - 新增 `StatusBarMetricGroup.logo`，允许 Logo 加入 `statusBarMetricOrder`，并在系统、网络和 Codex 项目之间自由排序。
  - 重构状态栏合成逻辑，将 Logo 和指标组按选择的顺序绘制到同一个 `NSImage` 中，并使用当前 `NSAppearance`。
  - 动态 Logo 通过 callback 提供更新后的图像；Logo 显示、随 CPU 加速和减少动态效果处理仍由 `StatusBarLogoConfiguration` 控制。
  - 隐私模式菜单项不再使用 `NSMenuItem` 的勾选状态，改为 SF Symbols，并关闭菜单状态列；关于、设置、刷新、隐私和退出菜单项均新增对应图标。
  - 使用基于 `UTType.text` 的拖放操作替代手动上下移动按钮，同时保留“恢复默认顺序”。

- 设置界面整理：
  - 将设置窗口重组为两列，并按外观、状态栏内容、系统指标样式、监控、传感器和系统选项进行分组。
  - 新增明确的字段标签，并调整窗口的最小尺寸和理想尺寸以适应扩展后的布局。

- 电源面板：
  - 当蓝牙设备超过两个时，使用紧凑的 48×48 电量环显示设备类型图标和电量百分比，不再为每个设备显示完整的 `BatteryRing` 行。
  - 通过 `.help` 和无障碍标签保留设备名称；隐私模式和电量不可用状态也分别提供对应文本。

- 平台与打包：
  - `Info.plist` 继续声明最低系统版本为 macOS `13.0`。
  - 传感器辅助进程流程继续在现有安装流程要求时使用管理员权限。
