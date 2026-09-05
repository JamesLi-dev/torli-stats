# Changelog

All notable changes to Torli Stats are documented here.

## [1.2.0] — 2026-09-05

### English
- Adds an optional WakaTime development-statistics Dashboard module with local macOS Keychain storage for the user’s API key. No WakaTime request is made until a key is configured and the module is enabled.
- Shows WakaTime coding time, AI Coding share, language usage, and—at detailed density—today’s time, active-day average, trailing 7- and 30-day totals, AI token totals, and model usage/cost information.
- Calculates trailing 7- and 30-day durations from date summaries, excluding today, to avoid inconsistent fixed-range statistics responses.
- Refreshes WakaTime data manually or every 30 minutes, with cached-data and request-failure status messaging.
- Limits the Dashboard popover to 820pt and adds an internal vertical scroll view with a compact inset overlay scroller for long module combinations.
- Refines Dashboard density by reducing the power ring and Codex/WakaTime progress-bar heights.
- Avoids repeated Keychain reads during Settings rendering, reducing unnecessary CPU use while the settings window is open.
- Adds a fixed 720 × 640 detail window with unified Typing and Development Statistics tabs, daily trends, period summaries, and privacy-preserving daily input records.
- Adds WakaTime daily coding trends, language/editor breakdowns, AI Coding, token, and model-cost details; the Dashboard card opens the corresponding tab.
- Makes settings updates targeted: appearance, layout, sampling, status-bar, Codex, sensor, and WakaTime changes now update only their related components. Codex text fields persist and synchronize after a short debounce.
- Keeps the Runner animated at a fixed 8 FPS when CPU acceleration is off; CPU acceleration continues to scale from 6 to 12 FPS. WakaTime range changes do not request data while the integration is disabled.
- Adds an integrated notes engine: animated edge deck, full note editor, Markdown and tasks, archive and search library, quick capture, global shortcuts, import/export, multi-display support, and encrypted SQLite persistence. Desktop notes are off by default and use Torli Stats’ update and launch-at-login settings; Option-drag the edge pill to either side at any height, or use the four-position shortcut in Notes Settings.

### 中文
- 新增可选的 WakaTime 开发统计 Dashboard 模块：用户 API Key 仅保存在本机 macOS 钥匙串；未配置 Key 或未启用模块时不会请求 WakaTime。
- 支持展示 WakaTime 编码时长、AI Coding 占比和语言使用情况；详细密度额外展示当天时长、活跃日均值、近 7/30 天时长、AI Token 汇总及模型用量/成本。
- 近 7 天与近 30 天时长改为按日期汇总计算，且不包含当天，避免固定范围统计接口出现不一致结果。
- 支持手动刷新或每 30 分钟自动刷新，并提供缓存数据和请求失败状态提示。
- Dashboard Popover 最大高度调整为 820pt；内容超出时使用内部纵向滚动，并采用带上下留白的紧凑 Overlay 滚动条。
- 微调 Dashboard 密度：缩小电源环形电量，以及 Codex/WakaTime 进度条高度。
- 设置界面不再在重复渲染时反复读取钥匙串，降低打开设置窗口时不必要的 CPU 占用。
- 新增固定 `720 × 640pt` 的统一详情窗口，包含输入统计与开发统计页签、每日趋势、周期概览及隐私保护的按日输入记录。
- 新增 WakaTime 每日编码趋势、语言/编辑器分布、AI Coding、Token 与模型成本明细；可从 Dashboard 卡片进入对应页签。
- 设置变更改为按项响应：外观、布局、采样、状态栏、Codex、传感器与 WakaTime 仅更新相关组件；Codex 文本输入会短暂防抖后再持久化和同步。
- 关闭“随 CPU 加速”后，Runner 保持固定 `8 FPS` 动画；开启时仍在 `6–12 FPS` 间动态调整。WakaTime 未启用时切换统计范围不会请求数据。
- 内置完整便签引擎：边缘 Deck 动画、完整编辑器、Markdown 与任务框、归档和搜索库、快速捕捉、全局快捷键、导入导出、多显示器支持与加密 SQLite 持久化。桌面便签默认关闭，更新和开机启动跟随 Torli Stats 主体；按住 Option 拖动边缘胶囊可停靠到左右侧任意高度，也可在便签设置中快速选择四个固定位置。
