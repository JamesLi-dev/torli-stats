# Changelog

All notable changes to Torli Stats are documented here.

## [1.5.0] — 2026-09-11

### English

- Adds privacy-preserving Codex Token activity tracking from local `token-count` events. Activity is shown as a Dashboard heatmap and is cached per Codex Home in a hashed system-cache path; conversation content is never stored or read.
- Adds activity heatmaps to Development Statistics for coding time and AI tokens, and to Typing Statistics for daily key counts across the retained year of local history.
- Refines the Statistics settings layout with consistent card surfaces, compact activity controls, localized labels, and clearer period, overview, and daily-detail sections.
- Revises memory reporting to estimate memory in use without file cache, report macOS memory pressure separately, and clarify the displayed status.
- Improves the Dashboard Codex card with compact token-activity spacing and account display behavior that keeps the first two accounts visible while allowing additional accounts to expand.
- Compresses Dashboard Development Statistics: standard density hides language rows, while detailed density limits language rows and keeps only the AI Coding and aggregate Token summaries.
- Adds a Bluetooth HID battery fallback for Apple accessories that macOS omits from `system_profiler`, and aligns every power device consistently in standard and detailed Dashboard grids.
- Refactors Notes editor and deck views, settings state, and statistics components into focused source files for easier maintenance.

### 中文

- 新增保护隐私的 Codex Token 活动统计：仅读取本地 `token-count` 事件，在 Dashboard 以热力图展示；缓存按 Codex Home 隔离并使用哈希化的系统缓存路径，不读取或保存对话内容。
- 开发统计新增编码时长与 AI Token 热力图；输入统计新增基于本地保留一年记录的每日键数热力图。
- 优化统计设置页布局，统一卡片背景与样式，精简活动切换控件，并改善统计周期、概览和每日明细的层次。
- 调整内存指标：估算不含文件缓存的已用内存，单独显示 macOS 内存压力，并明确状态含义。
- 优化 Dashboard Codex 卡片的 Token 活动间距与账号展示方式：默认显示前两个账号，其余账号可展开查看。
- 压缩 Dashboard 开发统计：标准密度隐藏语言列表；详细密度限制语言条目，并仅保留 AI Coding 与 Token 汇总。
- 为 macOS 未在 `system_profiler` 中返回电量的 Apple 蓝牙外设增加 HID 回退读取，并统一标准和详细模式下电源设备网格的排列。
- 按职责拆分 Notes 编辑器和 Deck 视图、设置状态及统计组件，便于后续维护。
