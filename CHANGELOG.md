# Changelog

All notable changes to Torli Stats are documented here.

## [1.1.3] — 2026-09-02

<!-- ai-changelog:780c40929e04 -->
### 2026-09-02

### English
- Adds optional typing statistics integration for the macOS menu-bar monitor.
- `TypingStatsService` uses a listen-only `CGEvent` tap after Input Monitoring permission is granted. It stores only daily eligible-key totals and active duration locally (up to 365 days), never input content, key codes, or app information.
- Adds Dashboard metrics for today’s input count, total count, active duration, and recent KPM; the menu bar uses a compact two-line “输入 / <count>键” presentation.
- Moves the System settings card to a full-width row, balancing the settings layout.
- Makes Codex initialization and protocol-response failures retryable, and keeps runner animation responsive while the first CPU sample is still zero during launch.
- Dashboard and settings now receive a shared `TypingStatsService` instance. Settings changes synchronize `typingStatsEnabled`, and service updates refresh the status-bar title.
- Adds the `typing` `DashboardModule` and `StatusBarMetricGroup`. The dashboard typing card defaults to enabled, while the status-bar typing item defaults to disabled.
- Adds `showTypingCard`, `showTypingStatusItem`, and `typingStatsEnabled` settings persisted through `UserDefaults`.
- The typing status-bar group is shown only when the relevant display setting and `typingStatsEnabled` are enabled and `TypingStatsService.permissionStatus == .monitoring`. It displays today’s key count using compact `k` formatting for values of 1,000 or more.
- Settings now expose a permission action through `onRequestTypingStatsPermission`, which calls `TypingStatsService.requestPermissionAndStart()`.
- Bumps `CFBundleShortVersionString` from `1.1.2` to `1.1.3` in `Info.plist`.

### 中文
- 为 macOS 菜单栏系统监视器增加可选的输入统计集成。
- `TypingStatsService` 在获得“输入监控”权限后使用只监听的 `CGEvent` tap；仅在本机保存每日有效按键数和活跃时长（最多 365 天），不保存输入内容、键码或应用信息。
- Dashboard 新增今日输入、累计输入、活跃时长和近期 KPM 指标；菜单栏使用紧凑的两行“输入 / <数量>键”展示。
- 将“系统”设置模块移到横跨整行的位置，平衡设置页布局。
- Codex 初始化和协议响应失败现在可以自动重试；启动时首个 CPU 样本仍为零时，Runner 动画会保持流畅。
- Dashboard 和设置页面现在共用同一个 `TypingStatsService` 实例。设置变更会同步 `typingStatsEnabled`，服务状态变化会刷新菜单栏标题。
- 新增 `typing` `DashboardModule` 和 `StatusBarMetricGroup`。输入卡片默认启用，菜单栏输入统计项默认关闭。
- 新增通过 `UserDefaults` 持久化的 `showTypingCard`、`showTypingStatusItem` 和 `typingStatsEnabled` 设置。
- 只有在对应显示设置和 `typingStatsEnabled` 均启用，且 `TypingStatsService.permissionStatus == .monitoring` 时，菜单栏才显示输入统计。今日按键数达到 1,000 或以上时使用紧凑的 `k` 格式显示。
- 设置页面新增权限操作，通过 `onRequestTypingStatsPermission` 调用 `TypingStatsService.requestPermissionAndStart()`。
- 在 `Info.plist` 中将 `CFBundleShortVersionString` 从 `1.1.2` 更新为 `1.1.3`。
