# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:12bd24ae57fa -->
### 2026-09-15

### English

- Torli Stats 1.5.1 refines the macOS menu-bar dashboard layout, popover sizing, sensor controls, and localized menu labels.

- Menu-bar sensor controls:
  - Adds `Refresh Sensors` and `Reinstall Sensor` actions to the context menu.
  - Both actions are disabled while `settings.sensorHelperChecking` is active.
  - The actions call `settings.refreshSensorStatus()` and `settings.installSensorHelper()`.
  - Shortens several existing English and Chinese menu labels, including refresh, monitoring, privacy, notes, settings, and quit actions.

- Dashboard and popover layout:
  - Introduces shared `DashboardLayout` constants for `panelWidth`, corner radii, section spacing, scroll-indicator inset, metric spacing, and density-specific metric-card heights.
  - Replaces the dashboard’s outer stack with `LazyVStack`, applies a rounded `AppColors.background` surface, and clips the dashboard to the shared popover shape.
  - Applies the shared `dashboardCardSurface()` styling to device information, metric cards, power status, process lists, Codex usage, and WakaTime usage.
  - Uses fixed metric-card heights of 58, 112, and 126 points for `.compact`, `.standard`, and `.detailed` densities.
  - Adds a `Spacer(minLength: 0)` inside non-compact metric cards to keep footer content aligned.
  - Updates `DashboardView.preferredHeight(for:codexAccountCount:)` to calculate height from visible dashboard blocks, density-specific spacing, Codex activity, WakaTime, and process rows.

- Popover sizing and update handling:
  - Centralizes the popover width through `DashboardView.panelWidth`.
  - Avoids assigning a new popover size when the height change is within 0.5 points.
  - Performs the fitting pass only while the popover is shown.
  - Adds `schedulePopoverSizeUpdate()` with a 0.12-second delayed, cancellable update for WakaTime changes.
  - Refreshes the calculated size when the popover opens and cancels pending size work during deinitialization.
  - Applies a continuous 12-point corner radius and masking to the `NSHostingController` view.

- Activity heatmap rendering:
  - Adds `.drawingGroup(opaque: false, colorMode: .linear)` to the heatmap grid rendering.

- Release metadata and platform declaration:
  - Updates `CFBundleShortVersionString` in `Info.plist` and `VERSION` from `1.5.0` to `1.5.1`.
  - `Info.plist` continues to declare `LSMinimumSystemVersion` as `15.0` and `LSUIElement` as enabled.

### 中文

- Torli Stats 1.5.1 优化 macOS 菜单栏面板的布局、弹窗尺寸调整、传感器操作以及菜单本地化文本。

- 菜单栏传感器操作：
  - 在右键菜单中新增“刷新传感器”和“重装传感器”操作。
  - 当 `settings.sensorHelperChecking` 为活动状态时，两个操作都会被禁用。
  - 对应操作分别调用 `settings.refreshSensorStatus()` 和 `settings.installSensorHelper()`。
  - 缩短英文和中文中的多个既有菜单文本，包括刷新、监控、隐私、便签、设置和退出等操作。

- 面板与弹窗布局：
  - 新增统一的 `DashboardLayout`，集中管理 `panelWidth`、圆角、区块间距、滚动指示器内边距、指标间距以及不同密度下的指标卡片高度。
  - 使用 `LazyVStack` 替代原有外层布局，为面板应用带圆角的 `AppColors.background` 背景，并裁剪为统一的弹窗形状。
  - 为设备信息、指标卡片、电源状态、进程列表、Codex usage 和 WakaTime usage 统一使用 `dashboardCardSurface()` 样式。
  - `.compact`、`.standard` 和 `.detailed` 密度下的指标卡片固定高度分别为 58、112 和 126。
  - 在非 compact 指标卡片中加入 `Spacer(minLength: 0)`，用于保持底部内容对齐。
  - 更新 `DashboardView.preferredHeight(for:codexAccountCount:)`，根据可见面板区块、密度间距、Codex activity、WakaTime 和进程行数计算面板高度。

- 弹窗尺寸与更新处理：
  - 通过 `DashboardView.panelWidth` 统一管理弹窗宽度。
  - 当高度变化不超过 0.5 点时，不再重复设置弹窗尺寸。
  - 仅在弹窗显示时执行 fitting pass。
  - 新增 `schedulePopoverSizeUpdate()`，对 WakaTime 更新使用 0.12 秒延迟且可取消的尺寸更新。
  - 弹窗打开时重新计算尺寸，并在析构时取消待处理的尺寸更新。
  - 为 `NSHostingController` 视图应用连续的 12 点圆角和裁剪。

- Activity heatmap 渲染：
  - 为热力图网格新增 `.drawingGroup(opaque: false, colorMode: .linear)`。

- 版本信息与平台声明：
  - 将 `Info.plist` 中的 `CFBundleShortVersionString` 和 `VERSION` 从 `1.5.0` 更新为 `1.5.1`。
  - `Info.plist` 仍声明 `LSMinimumSystemVersion` 为 `15.0`，并继续启用 `LSUIElement`。
