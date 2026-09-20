# Changelog

All notable changes to Torli Stats are documented here.

## [1.6.0] - 2026-09-20

### English
- Introduces a shared adaptive color system for Dashboard and Statistics views. Semantic accent, activity, success, caution, warning, and critical tokens now adapt consistently to light and dark appearances.
- Refines Dashboard process and network modules:
  - CPU, memory, download, and upload headers have consistent interactive sorting feedback.
  - Process CPU and memory values use aligned usage thresholds, while network lists reserve stable row space and animate rate updates without changing card height.
  - Improves battery accessory grid balance and aligns card-header icon rendering.
- Adds global menu-bar item spacing controls in Status Bar settings, with a `-8 pt` to `+8 pt` offset and a restore-system-default action.
  - Applying a spacing change updates the host-scoped macOS preference, refreshes SystemUIServer and ControlCenter, restarts compatible user menu-bar agents, and relaunches Torli Stats.
  - Foreground work apps and unsupported/system helper processes are not force-terminated; such items can retain their previous spacing until their owning app restarts.
- Improves Statistics overview sections by surfacing key period metrics directly, showing clearer no-data states, and hiding empty daily-detail lists.

### 中文
- 为 Dashboard 和统计页引入统一的自适应颜色系统。强调色、活动色、成功、提示、警告和严重状态等语义令牌现会在浅色与深色模式下保持一致。
- 改进 Dashboard 的高占用进程与网络模块：
  - CPU、内存、下载和上传标题提供一致的可交互排序反馈。
  - 进程 CPU 与内存数值采用统一的使用阈值；网络列表保留稳定的行空间，并在不改变卡片高度的情况下平滑更新速率。
  - 优化电池配件网格的平衡感，并统一卡片标题图标的层级渲染。
- 在状态栏设置中新增全局菜单栏项目间距控制，支持 `-8 pt` 至 `+8 pt` 偏移和恢复系统默认值。
  - 应用间距会更新 host-scoped macOS 偏好、刷新 SystemUIServer 和 ControlCenter、重启兼容的用户菜单栏代理，并重新启动 Torli Stats。
  - 不会强制终止前台工作 App、未受支持的进程或系统辅助进程；这类项目可能需在所属 App 重启后才会使用新间距。
- 优化统计概览区：直接展示周期关键指标、提供更清晰的无数据状态，并在没有活动时隐藏空的每日详情列表。
