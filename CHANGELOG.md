# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

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
