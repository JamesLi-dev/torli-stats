# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:b690a0b890a5 -->
### 2026-09-16

### English
- Replaces the dashboard `NSPopover` with a borderless `DashboardPanel` for custom rounded-corner rendering and positioning.
- Dashboard panel:
  - Positions itself relative to the status item within the screen’s `visibleFrame`, with edge fallbacks and an 8-point screen inset.
  - Preserves its top edge when `dashboardContentSize` changes.
  - Uses a nonactivating floating panel at `.popUpMenu` level with a shadow and transient collection behavior.
  - Explicitly updates monitoring visibility state when shown and dismissed.
- Improves outside-click handling by recognizing status-item events through both window identity and the button’s screen-space rectangle, preventing a status-item click from closing and immediately reopening the dashboard.
- Updates dashboard sizing and WakaTime refresh handling to use `dashboardPanel`, while retaining the existing height estimation and maximum height of 820 points.
- Refines dashboard presentation:
  - Increases `DashboardLayout.popoverCornerRadius` to 16.
  - Applies dark glass material for dark themes and the existing solid background for light themes.
  - Aligns the scroll-indicator inset with the panel corner radius.
  - Adds reusable `DashboardProgressBar` styling with clamped values, capsule rendering, configurable tint, and height.
- Uses `DashboardProgressBar` for disk usage, Codex quota, WakaTime language breakdowns, and AI Coding progress indicators.
- Makes `ThinScrollViewConfigurator` reapply scroll-view configuration during hierarchy, layout, and delayed main-thread passes, keeping overlay scroll indicators inset from rounded corners and preserving mini, auto-hiding vertical scroller settings.
- Bumps the application version from `1.5.1` to `1.5.2` in `Info.plist` and `VERSION`.
- No new permission declarations, persistence migrations, or migration code are introduced. `LSMinimumSystemVersion` remains `15.0`.

### 中文
- 使用无边框 `DashboardPanel` 替换 dashboard 的 `NSPopover`，以便自定义圆角表面和面板定位。
- Dashboard 面板：
  - 根据状态栏项目定位，并限制在屏幕 `visibleFrame` 内，同时保留 8 点屏幕边距和边缘回退逻辑。
  - 修改 `dashboardContentSize` 时保持顶部边缘位置不变。
  - 使用非激活浮动面板，级别为 `.popUpMenu`，启用阴影和 transient collection behavior。
  - 在显示和关闭时显式更新 monitoring visibility 状态。
- 改进外部点击处理：同时通过窗口身份和状态栏按钮的屏幕坐标矩形识别状态栏事件，避免状态栏点击先关闭 dashboard、再因 mouseUp 立即重新打开。
- 将 dashboard 尺寸调整和 WakaTime 刷新处理切换到 `dashboardPanel`，并保留现有高度估算逻辑及 820 点最大高度限制。
- 优化 dashboard 展示：
  - 将 `DashboardLayout.popoverCornerRadius` 提升为 16。
  - 深色主题使用 dark glass material，浅色主题继续使用现有纯色背景。
  - 让滚动指示器 inset 与面板圆角半径保持一致。
  - 新增可复用的 `DashboardProgressBar`，支持数值限制、胶囊形渲染、可配置颜色和高度。
- 使用 `DashboardProgressBar` 渲染磁盘使用率、Codex 配额、WakaTime 语言 breakdown 和 AI Coding 进度条。
- 让 `ThinScrollViewConfigurator` 在层级变化、布局以及延迟的主线程刷新中重复应用 scroll-view 配置，使 overlay scroll indicators 避开圆角区域，并保留 mini、自动隐藏的垂直滚动条设置。
- 在 `Info.plist` 和 `VERSION` 中将应用版本从 `1.5.1` 更新为 `1.5.2`。
- 本次 diff 未新增权限声明、持久化迁移或迁移代码。`LSMinimumSystemVersion` 仍为 `15.0`。
