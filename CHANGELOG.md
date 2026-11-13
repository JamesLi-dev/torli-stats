# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

## [1.12.5] - 2026-11-13

### English

- Prevent duplicate app processes and menu-bar items when launching another copy, including directly running the executable. Release the instance lock automatically on exit or crash, and detect already-running older versions during upgrades.
- Show the existing dashboard or settings window when the app is reopened, and preserve reopen requests received during startup.
- Guard against repeated menu-bar item creation and report failures to acquire the startup lock.

### 中文

- 防止重复启动产生多个进程和菜单栏图标，覆盖直接运行可执行文件的情况；退出或崩溃后自动释放占用，升级时识别已运行的旧版本。
- 再次打开应用时显示已有面板或设置窗口，启动期间收到的打开请求会在界面就绪后处理。
- 增加菜单栏重复创建保护，启动锁异常时显示明确错误。

## [1.12.4] - 2026-11-12

### English

- Add independently configurable CPU and GPU temperature indicators to the menu bar, including display ordering and sensor refresh.
- Share temperature colors with the dashboard: green below 65°C, orange from 65°C, dark orange from 80°C, and red from 90°C. Menu-bar values respect the usage-color setting.

### 中文

- 菜单栏新增 CPU、GPU 温度，可分别开启并调整显示顺序，温度随传感器采样刷新。
- 温度颜色与面板统一：低于 65°C 为绿色，65°C 起为橙色，80°C 起为深橙色，90°C 起为红色；菜单栏遵循现有用量颜色开关。

## [1.12.3] - 2026-11-11

### English

- Unify normal-temperature and battery greens with the dashboard palette while preserving warning colors.
- Keep dashboard updates responsive during interaction and prevent a closed Codex subprocess pipe from terminating the app.
- Include idle, memory-heavy processes when sorting by memory or combined usage; fix quoting of account paths containing apostrophes.
- Restrict sensor-helper connections to the installing app's code-signing requirement and restore automatic fan control only when the controlling connection disconnects. Reinstall the helper to enable these changes; ad-hoc signed app updates require reinstalling it again.

### 中文

- 正常温度和电池绿色统一使用面板配色，保留异常状态的警告颜色。
- 改善交互期间的面板刷新，避免 Codex 子进程管道提前关闭导致应用退出。
- 内存及综合排序保留 CPU 空闲但占用内存的进程，修复账号路径含单引号时的转义。
- 传感器助手按安装应用的签名要求校验连接，仅在控制风扇的连接断开时恢复自动模式。需重新安装助手才会生效；临时签名应用更新后需再次安装助手。

## [1.12.2] - 2026-11-09

### English

- Suspend dashboard-only disk, Bluetooth, process and per-application network sampling while the dashboard is closed; refresh them when it reopens.

### 中文

- 面板关闭时暂停仅供面板使用的磁盘、蓝牙、进程和按应用网络流量采集，重新打开时立即恢复刷新。

## [1.12.1] - 2026-11-05

### English

- Synchronize the sensor helper's current status when monitoring subscribes, preventing a completed startup probe from leaving fan and temperature sampling disabled until manual refresh.
- Retry transient startup failures, reconnect failed sensor connections, and resume failed sampling with a 30-second backoff.
- Improve the Community development-statistics card with a larger, left-aligned duration and a compact update-time layout.

### 中文

- 监控订阅建立时同步传感器当前状态，修复启动探测提前完成后风扇和温度采样未开启、需要手动刷新的问题。
- 启动连接暂时失败时自动重试，异常连接重新建立，采样失败后间隔至少 30 秒继续尝试。
- 优化普通版开发统计卡片：时长放大并靠左显示，更新时间紧凑排列，减少左侧空白。

## [1.12.0] - 2026-11-03

### English

- Add a shared, versioned Keychain container for WakaTime and Pro credentials, with verified writes, serialized feature updates, and migration from existing WakaTime OAuth storage. Pro keeps its TOTP payload encrypted separately.
- Improve dashboard tabs with icons and measured content heights; stabilize resizing and preserve header and CPU badge readability.
- Report credential-removal failures instead of showing a successful removal when the Keychain write failed.
- Existing Keychain items may still require individual permission during migration. Ad-hoc signed updates may require renewed access permission; TOTP identity verification remains separate.

### 中文

- 新增版本化统一钥匙串容器，供 WakaTime 与 Pro 凭据共用；写入后校验、串行更新各功能数据，并兼容迁移旧 WakaTime OAuth 凭据。Pro 的 2FA 内容仍单独加密。
- 面板分类增加图标，按实测内容高度调整面板，减少尺寸抖动并保持标题与 CPU 徽章完整显示。
- 删除凭据失败时显示错误，避免钥匙串写入失败后仍提示删除成功。
- 旧钥匙串项迁移期间仍可能逐条请求授权；临时签名更新可能再次要求许可，2FA 身份验证独立保留。

## [1.11.2] - 2026-11-02

### English

- Split the dashboard into Monitoring and Statistics tabs. Typing stays with system monitoring; Codex and WakaTime appear under Statistics. Remember the selected tab while preserving module visibility, relative order, and density preferences.
- Resize the panel for the selected category, with an 820-point maximum constrained by available screen height and internal scrolling for overflow. Keep device information and tab navigation above the scrolling content.
- Unify task-list editing in Notes and add Markdown divider support, including task layout and image-storage regression coverage.

### 中文

- 面板按“监控 / 统计”分类，输入统计保留在监控中，Codex 与 WakaTime 归入统计。记住所选分类，保留模块显示开关、相对顺序和密度设置。
- 面板随当前分类内容调整高度，上限为 820pt 且不超过屏幕可用高度，超出后内部滚动；设备信息和分类入口固定在滚动区上方。
- 便签统一任务列表编辑行为，增加 Markdown 分割线支持，并补充任务布局和图片存储回归测试。

## [1.11.1] - 2026-10-30

### English

- Migrate WakaTime statistics to personal OAuth tokens and Bearer authentication ahead of the November 1, 2026 API-key restriction. Add a token setup link, legacy-key migration guidance, and consistent 401/403 errors for today's usage and historical statistics. Tokens remain in the local Keychain.

### 中文

- WakaTime 统计改用个人 OAuth Token 和 Bearer 认证，适配 2026 年 11 月 1 日起 API Key 仅供插件使用的限制。新增 Token 获取入口及旧 Key 迁移提示，统一今日与历史统计的 401/403 错误说明。Token 仍仅保存在本机钥匙串。

## [1.11.0] - 2026-10-30

### English

- **Images in notes:** Insert PNG/JPEG files from the editor menu, paste screenshots, or drag files into a note. Resize images and crop freely or to preset aspect ratios, with undo/redo. Original image files remain intact when resizing or cropping.
- **Portable image backups:** Store attachments locally under `TorliStats/Notes/Images`. Include images in `.stickies` backups and export Markdown with relative image files; importing restores attachments and display widths. Existing text-only backups remain supported.
- **More reliable saving:** Debounce database writes while keeping open editors synchronized, retain failed changes for retry, and flush pending edits before quitting. Report storage failures instead of silently losing changes.
- **Better editing and deck behavior:** Continue task, bullet, and numbered lists with Enter; indent and outdent with Tab and Shift-Tab. Improve edge-deck transitions and upright Chinese/emoji labels, and add an option to keep notes on one Space.
- **Menu organization:** Group note actions separately in the menu-bar context menu.

### 中文

- **便签图片编辑：** 支持通过编辑器菜单插入 PNG/JPEG、粘贴截图和拖入图片；可缩放、自由裁剪或按预设比例裁剪，并支持撤销与重做。缩放和裁剪均保留原始图片文件。
- **图片备份与迁移：** 附件保存在本地 `TorliStats/Notes/Images` 目录；`.stickies` 备份完整携带图片，Markdown 导出附带相对路径图片文件，重新导入可恢复附件及显示宽度。继续兼容旧版纯文字备份。
- **保存可靠性：** 合并频繁的数据库写入，同时保持多个编辑窗口同步；写入失败时保留待保存内容并提示，退出前保存尚未落盘的修改。
- **编辑与侧边便签改进：** 回车续写任务、无序和有序列表，Tab / Shift-Tab 调整缩进；改进侧边便签切换动画和中文、表情标签的直立显示，新增将便签限制在单个桌面空间的选项。
- **菜单分组：** 菜单栏右键菜单中的便签操作独立分组。

## [1.10.0] - 2026-10-27

### English

- Separate the public community app from private Pro modules.
- Keep today's typing count, active time, KPM, and WakaTime coding time free. Historical typing and WakaTime analysis are available in Pro.
- Keep Codex quotas, multiple accounts, and Token activity in the community edition.
- Preserve local statistics when switching editions. Community refreshes only today's WakaTime data.
- Refine Codex account cards with compact quota rings.

### 中文

- 拆分公开社区版与私有 Pro 模块，社区版安装包不包含邮箱验证码及进阶统计页面。
- 今日输入次数、活跃时长、KPM 和 WakaTime 开发时长继续免费；输入与 WakaTime 的历史分析调整到 Pro。
- Codex 额度、多账号和 Token 活动继续保留在社区版。
- 切换版本时保留本地统计记录；社区版仅请求 WakaTime 今日数据。
- Codex 账号卡片采用紧凑布局和额度圆环。

## [1.9.0] - 2026-10-26

### English

- **Static menu-bar logos:** Choose Static or Animated explicitly. Static mode offers five new geometric marks plus Leaf, Sparkles, and Pulse, with no animation timer. Existing animation choices remain available.
- **Compact, aligned metrics:** Tighten menu-bar spacing, align localized typing labels with numeric values, and keep both rows visible without tab-based layout. Typing counts use compact values with the exact daily count in the tooltip.
- **Less background UI work:** Release the hidden dashboard view, skip unchanged typing-speed notifications and redundant status-title updates, and draw animated artwork separately from the title. Continuous animation still has a measurable CPU cost.
- **Dashboard improvements:** Remove the bottom gradient that could obscure content and add a direct toggle for Codex token activity in dashboard settings.

### 中文

- **静态状态栏 Logo：** 明确区分静态与动画模式。静态模式提供五款新几何图标，以及叶片、星芒、脉冲，不启动动画计时器；原有动画样式继续保留。
- **紧凑且对齐的指标：** 收紧状态栏间距，处理中文输入标签与数字的对齐，并避免制表位导致的双行内容裁切。输入计数使用紧凑显示，悬停可查看当天准确数量。
- **减少后台界面刷新：** 面板隐藏后释放视图，跳过未变化的输入速度通知和重复标题更新，动画图像与文字分开绘制。持续播放动画仍有一定 CPU 开销。
- **面板改进：** 移除可能遮挡内容的底部渐变，并在面板设置中增加 Codex Token 活动开关。

## [1.8.1] - 2026-10-20

### English

Torli Stats 1.8.1 improves fan-control feedback and makes Cool mode adapt to heat.

- **Adaptive cooling:** Cool starts at 40% of the reported maximum RPM, then raises the target to 60%, 80%, or 100% as CPU/GPU temperature or CPU load increases. Max remains full speed; Auto returns control to macOS.
- **Accurate fan percentage:** The dashboard badge and progress ring now show measured RPM relative to the reported maximum, rather than the selected control preset.
- **Transition feedback:** The fan card shows “Starting…” while a manual target is taking effect, until measured RPM approaches its target or 15 seconds elapse.
- **Sensor helper update:** Fan control now requires Sensor Helper 1.4 (protocol v5). Reinstall the helper after updating to use the new cooling strategy.

### 中文

Torli Stats 1.8.1 改进了风扇控制反馈，并让降温模式随热量自动调整。

- **自适应降温：** 降温从上报最大 RPM 的 40% 起步，随后会按 CPU/GPU 温度或 CPU 负载提升至 60%、80% 或 100%。强冷保持全速，自动模式仍交由 macOS 控制。
- **准确的风扇百分比：** 面板徽标和进度环现在显示实际 RPM 相对上报最大转速的比例，不再显示所选控制预设值。
- **过渡状态反馈：** 手动目标生效期间，风扇卡片显示“启动中”，直到实际 RPM 接近目标值或经过 15 秒。
- **传感器辅助进程更新：** 风扇控制现要求 Sensor Helper 1.4（协议 v5）。更新后请重新安装辅助进程，以启用新的降温策略。
