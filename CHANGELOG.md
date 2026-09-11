# Changelog

All notable changes to Torli Stats are documented here.

## [1.4.2] — 2026-09-11

### English

- Adds optional local Codex CLI activity tracking with daily active duration, latest active time, and a seven-day trend.
- Restricts activity tracking to checking whether a `codex` process exists; terminal content, command arguments, project paths, and input are never recorded.
- Displays Codex Credits, unlimited-credit status, and rate-limit warnings alongside quota information and recent refresh details.
- Adds a menu-bar Codex account display limit of one, two, or three accounts, while keeping the Dashboard collapsed to at most two accounts before expanding.
- Adds confirmation before removing a Torli Stats-managed Codex account and clarifies that the local Codex Home and sign-in state are preserved.
- Refreshes the settings sidebar spacing and icon sizing, and aligns typing chart bars with the development statistics blue.

### 中文

- 新增可选的本地 Codex CLI 活跃统计，显示每日活跃时长、最近活跃时间和近 7 天趋势。
- 活跃统计仅检测是否存在 `codex` 进程，不记录终端内容、命令参数、项目路径或输入内容。
- 在额度信息旁显示 Codex Credits、Credits 不限量状态和限额提示，并保留最近刷新信息。
- 菜单栏 Codex 逐账号模式新增显示 1、2 或 3 个账号的上限；面板仍默认最多展示两个账号，其他账号可展开查看。
- 移除 Torli Stats 管理的 Codex 账号前增加确认，并明确保留本机 Codex Home 和登录状态。
- 优化设置侧栏图标与文字间距和图标尺寸，并将输入统计柱图统一为开发统计使用的蓝色。

## [1.4.1] — 2026-09-10

### English

- Refreshes Note typography with a clearer reading-oriented font list: System, Helvetica Neue, PingFang SC, Songti SC, Palatino, and Menlo.
- Adds optional code-oriented faces—Maple Mono, Fira Code, Space Mono, and PT Mono—when installed on the Mac.
- Retires the former handwriting-style and legacy choices. Existing selections of retired fonts safely fall back to System.

### 中文

- 更新 Note 字体列表，提供更清晰易读的 System、Helvetica Neue、PingFang SC、Songti SC、Palatino 和 Menlo。
- 新增 Maple Mono、Fira Code、Space Mono 与 PT Mono 等代码风格字体；仅在 Mac 已安装对应字体时显示。
- 移除原有手写风格和旧字体选项；已选择被移除字体的用户会自动回退至系统字体。

## [1.4.0] — 2026-09-10

<!-- ai-changelog:3d322e73c0ef -->

### English

- Torli Stats 1.4.0 adds configurable monitoring pause behavior, richer battery and process information, and additional dashboard/status-bar display settings.

- Monitoring:
  - Adds manual pause/resume through the status-bar menu.
  - Adds `manual` and `dashboardClosed` pause reasons with localized dashboard and resume messages.
  - Supports persisted `manualMonitoringPaused` and `backgroundMonitoringEnabled` settings.
  - Resolves monitoring state across manual pause, system sleep, display sleep, screen lock, night schedule, dashboard visibility, and adaptive sampling.
  - Keeps explicit refreshes available while automatic sampling is paused.
  - Pauses automatic Codex, WakaTime, and typing-stat refresh work during paused states; adaptive low-frequency mode continues to affect local metric sampling separately.
  - Re-evaluates monitoring when the new settings change.

- Dashboard:
  - Adds persisted toggles for `showDashboardDeviceInfo`, `showTemperatureTags`, and `showProcessPID`; all default to enabled and are included in `resetToDefaults()`.
  - Device information, CPU/GPU temperature tags, and detailed process PIDs can now be hidden independently.
  - Popover sizing is recalculated when these dashboard display settings change.
  - Process columns now follow `processSort`: CPU, memory, or both for `combined`; PID remains available only in detailed density when enabled.

- Battery and thermal status:
  - `BatterySnapshot` now includes `SystemThermalState`, mapped from `ProcessInfo.ThermalState`; unknown thermal states are treated as `critical`.
  - Non-compact power views display a localized thermal-status tag alongside battery health and cycle count.
  - Battery ring colors now distinguish low, warning, moderate, and normal levels; health and thermal states use corresponding severity colors.
  - Bluetooth battery rings use each device’s battery level color, including compact layouts.

- Process ranking and status data:
  - `ProcessReader` adds `ProcessSortOption.combined`, ranking processes by normalized CPU plus normalized memory usage before applying the configured limit.
  - `MetricsStore` now passes raw download and upload rates into `StatusLine` instead of formatting them there.
  - New persisted status-bar settings include `statusBarFontSize`, `showStatusBarMetricIcons`, `networkRateUnit`, and `networkRateDecimalPlaces`; changes to these settings trigger a status-bar title update.

- Release and platform constraints:
  - `CFBundleShortVersionString` is updated from `1.3.0` to `1.4.0`.
  - `LSMinimumSystemVersion` remains `15.0`.
  - No new permission declarations are added in `Info.plist`; adaptive idle detection continues to use the permission-free `CGEventSource.secondsSinceLastEventType` path shown in the implementation.

### 中文

- Torli Stats 1.4.0 新增可配置的监控暂停行为、更丰富的电池与进程信息，以及额外的 Dashboard 和状态栏显示设置。

- 监控：
  - 状态栏菜单新增手动暂停/恢复监控入口。
  - 新增 `manual` 和 `dashboardClosed` 暂停原因，并提供对应的 Dashboard 与恢复提示本地化文本。
  - 新增持久化设置 `manualMonitoringPaused` 和 `backgroundMonitoringEnabled`。
  - 监控状态现在综合处理手动暂停、系统睡眠、显示器睡眠、屏幕锁定、夜间计划、Dashboard 可见性和自适应采样。
  - 自动采样暂停时仍保留显式刷新能力。
  - 暂停状态下会暂停 Codex、WakaTime 和 typing 的自动刷新；自适应低频模式仍单独影响本地指标采样。
  - 新增设置发生变化时会重新评估监控状态。

- Dashboard：
  - 新增持久化开关 `showDashboardDeviceInfo`、`showTemperatureTags` 和 `showProcessPID`；默认均为启用，并纳入 `resetToDefaults()`。
  - 设备信息、CPU/GPU 温度标签以及详细进程 PID 现在可以分别隐藏。
  - 这些 Dashboard 显示设置变化时会重新计算弹出面板尺寸。
  - 进程列现在跟随 `processSort` 显示：CPU、内存，或 `combined` 模式下同时显示两者；PID 仅在启用且密度为详细模式时显示。

- 电池与温度状态：
  - `BatterySnapshot` 新增 `SystemThermalState`，由 `ProcessInfo.ThermalState` 映射而来；未知温度状态按 `critical` 处理。
  - 非紧凑模式的电源视图会在电池健康度和循环次数旁显示本地化温度状态标签。
  - 电池环现在区分低电量、警告、中等和正常电量，并为健康度与温度状态使用相应严重程度颜色。
  - Bluetooth 电池环会根据各设备自身电量显示颜色，紧凑布局同样适用。

- 进程排序与状态数据：
  - `ProcessReader` 新增 `ProcessSortOption.combined`，按照归一化 CPU 使用率与归一化内存使用量之和对进程排序，再应用配置的数量限制。
  - `MetricsStore` 现在向 `StatusLine` 传递原始下载和上传速率，不再在此处预先格式化。
  - 新增持久化状态栏设置 `statusBarFontSize`、`showStatusBarMetricIcons`、`networkRateUnit` 和 `networkRateDecimalPlaces`；这些设置变化会触发状态栏标题更新。

- 发布版本与平台限制：
  - `CFBundleShortVersionString` 从 `1.3.0` 更新为 `1.4.0`。
  - `LSMinimumSystemVersion` 仍为 `15.0`。
  - `Info.plist` 未新增权限声明；实现中继续使用标注为无需权限的 `CGEventSource.secondsSinceLastEventType` 路径进行自适应空闲检测。
