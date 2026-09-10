# Changelog

All notable changes to Torli Stats are documented here.

## [1.3.0] — 2026-09-10

### English
- Redesigns Torli Stats, Torli Notes, and detailed-statistics preferences with compact left-side navigation and a consistent right-side detail layout.
- Unifies their neutral light/dark surfaces and adds a native frosted-glass background that extends through the titlebar, while retaining readable material setting cards.
- Shows the specific monitoring-pause reason in Dashboard, such as night schedule, screen lock, display sleep, or system sleep.
- Avoids redundant adaptive-sampling broadcasts and timer recreation; pause state and its Dashboard message now update atomically, while inactive Settings windows reduce visual-effect compositing work.
- Refines Notes settings and library-window spacing, alignment, and compact sizing; navigation shortcuts appear last and inactive navigation rows no longer draw a blue focus ring.
- Brightens the shared Settings glass surface to reduce wallpaper colour cast, and adds constrained, column-following daily-chart tooltips for typing and development details.
- Adds date ticks to detailed daily charts, and refines the Notes library with a compact, theme-aware glass shell that preserves each note's readable paper colour.
- Makes the Notes library sidebar an AppKit-native splitter with a persisted 180–340pt width and a 200pt default, avoiding editor flicker while resizing.
- Checks GitHub's latest-release redirect instead of its rate-limited REST API, so update checks remain available on shared networks.
- Stops low-frequency disk, Bluetooth, process, and sensor reads when no visible Dashboard module needs them, while retaining battery reads for power policy decisions.
- Reduces each automatic WakaTime refresh from five requests to three by fetching only the selected breakdown and deriving the 7-day trend from the 30-day summary; the alternate breakdown loads only when its detail view is opened.
- Consolidates Notes preferences into the main Settings window, with existing Notes menu and Deck entry points opening its new Notes page.
- Establishes an application-wide language preference shared by Torli Stats and Torli Notes, preserving the existing System Default, English, and Simplified Chinese choices.
- Completes English and Simplified Chinese coverage across Settings, Dashboard, statistics, WakaTime, Codex, sensors, status-bar content, diagnostics, tooltips, and accessibility labels; adds a safe Restart action when a language change needs relaunching.
- Moves Typing and Developer Statistics into the main Settings window as a dedicated Statistics page, so all preferences and detailed metrics share one navigation surface.
- Refines Settings visual consistency with aligned sidebar icons, responsive Menu Bar controls, compact English labels, and matching material cards for Notes and Statistics pages.
- Makes legacy installed sensor helpers return localized diagnostic text and corrects localized numeric-format paths that could otherwise display corrupted values or crash.

### 中文
- 重构 Torli Stats、Torli Notes 与详细统计窗口：使用紧凑的左侧导航和统一的右侧详情布局。
- 统一亮色与暗色下的中性配色，并加入延伸至标题栏的原生毛玻璃背景，同时保留清晰可读的材质化设置卡片。
- Dashboard 现在会按夜间时段、屏幕锁定、显示器休眠或系统睡眠展示具体的监控暂停原因。
- 避免智能采样的冗余状态广播与定时器重建；暂停状态和 Dashboard 文案改为原子更新，设置窗口失焦后也会减少毛玻璃合成开销。
- 优化便签设置与所有便签窗口的间距、对齐和紧凑尺寸；快捷键移至导航末尾，未选中导航项不再显示蓝色焦点框。
- 提亮统一设置毛玻璃表面以减少壁纸色偏，并为输入统计和开发统计加入受边界约束、随柱子横向移动的每日 Tooltip。
- 为详细统计的每日图表补充日期刻度，并优化所有便签窗口：使用紧凑且跟随主题的毛玻璃外壳，同时保留每张便签清晰可读的纸张主体色。
- 所有便签左栏改为 AppKit 原生可调分栏，宽度可在 180–340pt 间调整、默认 200pt 且会记忆；拖动时不再引发编辑器闪动。
- 更新检查改用 GitHub 最新发布页面的跳转地址，不再依赖容易触发限额的 REST API，共享网络下也能正常检查更新。
- 未显示对应 Dashboard 模块时，不再进行低频磁盘、蓝牙、进程和传感器读取；电池读取仍会保留，以支持电源策略判断。
- WakaTime 自动刷新从每次 5 个请求降至 3 个：仅请求当前选择的概览，并由 30 天汇总推导近 7 天趋势；另一周期的概览仅在打开其详情时按需加载。
- 便签设置已并入主设置窗口；菜单和便签栏入口会直接打开新的“便签”页面。
- 建立由 Torli Stats 与 Torli 便签共用的应用语言偏好，保留原有的跟随系统、English 与简体中文选项。
- 完成 Settings、Dashboard、统计、WakaTime、Codex、传感器、状态栏、诊断、Tooltip 与无障碍文案的 English / 简体中文覆盖；语言变更需要重启时提供安全的“重启”操作。
- 输入统计与开发统计已并入主设置窗口的“统计”页面，偏好与详细指标共用同一套导航入口。
- 统一设置视觉细节：对齐侧栏图标，优化状态栏设置的自适应布局和英文短文案，并为便签、统计页面补齐一致的材质化圆角卡片。
- 兼容旧版已安装传感器辅助进程的诊断文案本地化，并修复可能显示异常数值或导致闪退的本地化数字格式路径。

## [1.2.2] — 2026-09-08

### English
- Adds night monitoring pause, enabled by default from 23:30 to 07:00. It stops automatic metric, sensor, input-statistics, Codex, and WakaTime work during quiet hours and resumes safely after wake.
- Adds an optional adaptive low-impact sampling mode. After 25 minutes of idle time, local metric sampling slows to 30 / 120 seconds and the status-bar Runner pauses; opening the Dashboard restores real-time sampling.

### 中文
- 新增夜间暂停监控，默认在 23:30–07:00 停止自动指标、传感器、输入统计、Codex 与 WakaTime 工作，并在唤醒后安全恢复。
- 新增可选的智能节能采样：连续空闲 25 分钟后，本地指标采样降至 30 / 120 秒，状态栏 Runner 暂停；打开 Dashboard 后恢复实时采样。

## [1.2.1] — 2026-09-05

### English
+- Reorganizes the application into focused Application, Dashboard, Metrics, Settings, StatusBar, and UI source modules without changing user-facing behavior.
+- Avoids re-laying out the status-bar Runner when an animation frame has unchanged geometry, reducing its idle CPU use while preserving the existing 6–12 FPS acceleration and fixed 8 FPS mode.
+- Updates Codex usage view callbacks to the current macOS 14 SwiftUI `onChange` API.
+
+### 中文
+- 将应用源码按 Application、Dashboard、Metrics、Settings、StatusBar 与 UI 职责拆分，用户可见行为保持不变。
+- Runner 动画帧尺寸不变时不再重复触发状态栏布局；在保留 `6–12 FPS` CPU 加速和固定 `8 FPS` 模式的前提下降低空闲 CPU 占用。
+- 将 Codex 用量视图回调更新为 macOS 14 的 SwiftUI `onChange` API。
+
+## [1.2.0] — 2026-09-05

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
