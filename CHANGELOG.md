# Changelog

All notable changes to Torli Stats are documented here.

## [1.1.4] — 2026-09-02

### English
- Adds a 7-day input trend to the Dashboard input card and an independent input-history window with 7-day and 30-day views, daily totals, average, peak, active duration, and zero-input days preserved in the timeline.
- Fixes input-history loading so opening or restarting the app does not overwrite existing data with an empty record for today.
- Replaces per-frame full status-bar image composition with a layered status-bar view: metrics text is refreshed only when metrics change, while the Runner updates independently.
- Limits Runner animation to 6–12 FPS, coalesces input-stat status-bar refreshes, and reduces GPU `ioreg` sampling to at most once every 10 seconds when the GPU card is visible. GPU sampling stops when that card is hidden.

### 中文
- Dashboard 的输入卡新增近 7 天趋势；新增独立的输入统计详情窗口，支持近 7 天与近 30 天切换、每日键数、日均、最高值、活跃时长，并在时间轴中保留无输入日期。
- 修复输入历史加载问题：打开或重启应用不会再以当天的空记录覆盖已有数据。
- 状态栏改为分层渲染：指标文字仅在指标变化时更新，Runner 独立更新，避免每帧合成整张状态栏图片。
- Runner 动画限制为 6–12 FPS；输入统计状态栏刷新会合并；GPU 卡片可见时 `ioreg` 最多每 10 秒读取一次，隐藏 GPU 卡片时停止采样。
