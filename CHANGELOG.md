# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:a2f0acd5b207 -->
### 2026-08-30

### English
- Torli Stats is prepared for the `1.0.0` release with privacy controls, menu-bar quick actions, diagnostic information, and centralized version management.

- **Privacy mode**
  - Adds a persisted `privacyMode` setting, disabled by default and reset to `false` by `resetToDefaults()`.
  - Adds a right-click menu toggle, with the current state shown through the menu item checkmark.
  - Replaces the dashboard Mac model with `此 Mac`.
  - Replaces Bluetooth device names with `蓝牙设备 1`, `蓝牙设备 2`, and so on.
  - Replaces Codex dashboard account names with `Codex 1`, `Codex 2`, and so on.
  - Replaces Codex status-bar account prefixes with `COD1`, `COD2`, and so on, and omits status-bar account email values.
  - Other displayed metrics, including CPU model, memory, system version, uptime, battery details, and Codex usage percentages, remain unchanged by this setting.

- **Menu-bar actions and app information**
  - Adds `刷新全部数据`, which calls `MetricsStore.refreshNow()` and `CodexAccountsUsageStore.refresh()`.
  - Adds `打开设置` with the `,` key equivalent.
  - Adds `关于 Torli Stats`, displaying `CFBundleShortVersionString`, `CFBundleVersion`, the detected `arm64`/`x86_64` architecture label, the macOS version, and sensor helper status.
  - The About dialog can copy diagnostic text to `NSPasteboard.general` or open the bundled `THIRD_PARTY_NOTICES.md`.
  - Context-menu actions remain localized in Chinese and include the existing quit action.

- **Refresh behavior**
  - Adds `MetricsStore.refreshNow()`, scheduling high-frequency and low-frequency metric collection on their existing background queues.

- **Versioning and release tooling**
  - Adds `VERSION` with the initial semantic version `1.0.0`.
  - `build-app.sh` reads and validates `VERSION`, writes it to `CFBundleShortVersionString`, and derives `CFBundleVersion` from the Git commit count unless `BUILD_NUMBER` is provided.
  - Adds `scripts/bump-version.sh` for `major`, `minor`, and `patch` updates to both `VERSION` and `Info.plist`.
  - README release instructions now use `v1.0.0` and document `VERSION`, `BUILD_NUMBER`, and `tag v$(cat VERSION)`.
  - The existing build remains constrained to macOS 13 or later and continues to use the configured code-signing identity; the documented sensor helper flow requires the app to be in `/Applications`.

- **Project tracking**
  - `TODO.md` removes checklist entries for dashboard/process scrolling, opening-panel refresh, notifications, historical data, and several quick actions, reflecting updates to the tracked work items.

- **Validation**
  - `build-app.sh` and `scripts/bump-version.sh` reject versions that do not match `MAJOR.MINOR.PATCH`; no test execution or build result is evidenced in the provided diff.

### 中文
- Torli Stats 已准备进入 `1.0.0` 版本，新增隐私展示控制、菜单栏快捷操作、诊断信息和集中式版本管理。

- **隐私模式**
  - 新增持久化的 `privacyMode` 设置，默认关闭，`resetToDefaults()` 会将其恢复为 `false`。
  - 右键菜单新增隐私模式切换项，并通过菜单项勾选状态显示当前状态。
  - Dashboard 中的 Mac 型号替换为 `此 Mac`。
  - 蓝牙设备名称替换为 `蓝牙设备 1`、`蓝牙设备 2` 等编号。
  - Codex Dashboard 账号名称替换为 `Codex 1`、`Codex 2` 等编号。
  - Codex 状态栏账号前缀替换为 `COD1`、`COD2` 等编号，并隐藏状态栏中的账号邮箱值。
  - CPU 型号、内存、系统版本、运行时间、电池详情和 Codex 使用百分比等其他指标不受该设置影响。

- **菜单栏操作和应用信息**
  - 新增 `刷新全部数据`，调用 `MetricsStore.refreshNow()` 和 `CodexAccountsUsageStore.refresh()`。
  - 为 `打开设置` 增加 `,` 快捷键。
  - 新增 `关于 Torli Stats`，显示 `CFBundleShortVersionString`、`CFBundleVersion`、检测到的 `arm64`/`x86_64` 架构标签、macOS 版本和传感器辅助进程状态。
  - 关于窗口可以将诊断文本复制到 `NSPasteboard.general`，或打开应用内置的 `THIRD_PARTY_NOTICES.md`。
  - 菜单栏操作继续使用中文，并保留原有的退出操作。

- **刷新行为**
  - 新增 `MetricsStore.refreshNow()`，通过现有的后台队列分别调度高频和低频指标采集。

- **版本和发布工具**
  - 新增 `VERSION`，初始语义化版本为 `1.0.0`。
  - `build-app.sh` 读取并校验 `VERSION`，将其写入 `CFBundleShortVersionString`；除非提供 `BUILD_NUMBER`，否则使用 Git commit 数量生成 `CFBundleVersion`。
  - 新增 `scripts/bump-version.sh`，支持 `major`、`minor` 和 `patch`，同时更新 `VERSION` 与 `Info.plist`。
  - README 中的发布示例更新为 `v1.0.0`，并补充 `VERSION`、`BUILD_NUMBER` 和 `tag v$(cat VERSION)` 的说明。
  - 现有构建仍要求 macOS 13 或更高版本，并继续使用配置的 code-signing identity；文档中的传感器辅助进程安装流程要求应用位于 `/Applications`。

- **项目跟踪**
  - `TODO.md` 移除了 Dashboard/进程滚动、打开面板时刷新、通知、历史数据以及若干快捷操作相关条目，反映跟踪清单的更新。

- **Validation**
  - `build-app.sh` 和 `scripts/bump-version.sh` 都会拒绝不符合 `MAJOR.MINOR.PATCH` 格式的版本；提供的 diff 中没有执行测试或构建结果。
