# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:manual-1.5.3 -->
### 2026-09-16

### English
- Bumps the application version from `1.5.2` to `1.5.3` in `Info.plist` and `VERSION`.
- Improves Dashboard runtime feedback:
  - Animates metric values, CPU/input charts, progress bars, battery rings, heatmap mode changes, and panel presentation.
  - Adds actionable empty states for input monitoring, WakaTime, Codex, and sensor access.
  - Uses a shared `DashboardChip` component for system, status, account, and range labels.
  - Adds chart baselines and safer text compression/truncation for narrow cards.
  - Limits hover elevation to interactive cards and gives icon buttons hover/pressed feedback.
- Keeps the Dashboard scrollable with mouse-wheel and trackpad input while hiding the native scroll indicator.
- No new permission declarations, persistence migrations, or migration code are introduced. `LSMinimumSystemVersion` remains `15.0`.

### 中文
- 在 `Info.plist` 和 `VERSION` 中将应用版本从 `1.5.2` 更新为 `1.5.3`。
- 改进 Dashboard 运行时反馈：
  - 为指标数值、CPU/输入图表、进度条、电池环、Heatmap 模式切换和面板展示增加动画。
  - 为输入监控、WakaTime、Codex 和传感器访问增加可操作的空状态。
  - 使用统一的 `DashboardChip` 组件渲染系统、状态、账户和范围标签。
  - 增加图表基准线，并改善窄卡片中的文本压缩和截断处理。
  - 仅可交互卡片显示悬停抬升效果，图标按钮增加悬停和按下反馈。
- Dashboard 继续支持鼠标滚轮和触控板滚动，同时隐藏原生滚动指示器。
- 本次修改未新增权限声明、持久化迁移或迁移代码。`LSMinimumSystemVersion` 仍为 `15.0`。
