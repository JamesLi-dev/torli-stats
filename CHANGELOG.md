# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:91f64aa34c41 -->
### 2026-10-12

### English

Torli Stats 1.7.0 adds a more informative fan card, revises CPU temperature selection, and allows sensor readings to refresh more frequently.

- **Fan display:** Standard and detailed dashboard layouts show RPM beside a fan rotor and progress ring. When a positive maximum RPM is available, the card displays a percentage capped at 100% and a maximum-RPM footer. Compact layout keeps the numeric value with a percentage badge, falling back to an `RPM` badge when the maximum is unavailable.
- **Fan animation and accessibility:** `DashboardFanRotor` maps the current-to-maximum RPM ratio to a deliberately slowed visual rotation using `0.25 + clampedFraction * 1.75` revolutions per second, rather than physical fan speed. `TimelineView` uses a minimum interval of `1.0 / 24.0` seconds. The rotor remains static when Reduce Motion is enabled or the fraction is zero, and the decorative view is hidden from accessibility. Ring and rotor colors use success below 65%, warning from 65%, and critical from 85%; an unavailable maximum produces a static, secondary-colored rotor.
- **Fan sensor data:** The helper reads each valid fan’s corresponding `F…Mx` maximum-speed key and pairs the highest current RPM with that same fan’s limit. Current readings must be at least zero and below 20,000 RPM; maximum readings must be positive and below 20,000 RPM. The optional `fanMaxRPM` field passes through the XPC response, `PrivilegedSensorValues`, and `MetricsStore`, and is cleared when the helper or sensor readings are disabled.
- **CPU temperature selection:** The helper now prefers `TCMb`, followed by `TCDX`, `TC0P`, and `TCMz`. If those are unavailable, it uses the median of recognized Apple Silicon CPU cluster readings instead of the hottest cluster, with the median of all recognized CPU candidates as the final fallback. This changes the displayed CPU temperature’s basis toward a representative reading; SMC key availability still varies by machine.
- **Sensor refresh scheduling:** High-frequency collection now also queues sensor polling on `lowMetricsQueue`. Automatic requests share a five-second throttle based on `ProcessInfo.processInfo.systemUptime`; actual cadence still depends on collection intervals and queue scheduling. Forced polling bypasses the throttle. Existing helper-enabled, sensor-needed, pause, and failed-session guards remain in place, and changing helper authorization or disabling sensor readings resets the throttle timestamp.
- **Shared UI and localization:** `MetricCard` omits empty value text and empty badge chips, allowing the fan row to supply its own large RPM value. English and Simplified Chinese resources replace `dashboard.current_speed` with `dashboard.fan_percent` and `dashboard.fan_summary`.
- **Version and helper migration:** `VERSION` and `CFBundleShortVersionString` advance from `1.6.1` to `1.7.0`; `helperVersion` changes from `"1.0"` to `"1.1"` and `protocolVersion` from `1` to `2`. The revised CPU selection and maximum-RPM reporting require the updated helper. The client treats a missing `fanMaxRPM` field as unavailable; this diff does not show an automatic helper-upgrade mechanism. Sensor access continues through a privileged `NSXPCConnection`, and `LSMinimumSystemVersion` remains `15.0`.

### 中文

Torli Stats 1.7.0 丰富了风扇卡片的信息展示，调整了 CPU 温度的取值方式，并让传感器读数有机会更频繁地刷新。

- **风扇显示：** 标准和详细面板布局在风扇转子与进度环旁显示 RPM。当最大转速有效且大于零时，卡片显示最高为 100% 的转速百分比，并在底部标注最大 RPM。紧凑布局保留转速数值和百分比徽标；无法获取最大转速时，徽标回退为 `RPM`。
- **风扇动画与辅助功能：** `DashboardFanRotor` 根据当前转速与最大转速之比，以 `0.25 + clampedFraction * 1.75` 圈/秒呈现刻意放慢的旋转效果，不对应风扇的实际旋转速度。`TimelineView` 的最小更新间隔为 `1.0 / 24.0` 秒。开启“减少动态效果”或比例为零时，转子保持静止；这一装饰视图对辅助功能隐藏。进度环与转子在低于 65% 时使用成功色，从 65% 起使用警告色，从 85% 起使用严重状态色；最大转速不可用时，转子静止并使用次要颜色。
- **风扇传感器数据：** 辅助进程读取每个有效风扇对应的 `F…Mx` 最大转速键，并将最高的当前 RPM 与同一风扇的转速上限配对。当前转速必须大于等于零且低于 20,000 RPM；最大转速必须大于零且低于 20,000 RPM。可选字段 `fanMaxRPM` 经 XPC 响应、`PrivilegedSensorValues` 传入 `MetricsStore`，并在禁用辅助进程或传感器读取时清空。
- **CPU 温度取值：** 辅助进程现在优先采用 `TCMb`，随后依次尝试 `TCDX`、`TC0P` 和 `TCMz`。这些读数不可用时，改用已识别的 Apple Silicon CPU 簇温度中位数，替代此前的最高簇温度；最后回退到所有已识别 CPU 候选读数的中位数。这使显示值的取值依据更偏向代表性温度；SMC 键是否可用仍取决于具体机型。
- **传感器刷新调度：** 高频采集现在也会向 `lowMetricsQueue` 提交传感器轮询。自动请求共用基于 `ProcessInfo.processInfo.systemUptime` 的五秒节流限制，实际刷新周期仍取决于采集间隔和队列调度；强制轮询可绕过该限制。现有的辅助进程启用状态、传感器读取需求、暂停状态和会话失败检查继续生效。辅助进程授权状态变化或禁用传感器读取时，会重置节流时间戳。
- **共用界面与本地化：** `MetricCard` 不再渲染空值文本和空徽标，让风扇行自行呈现大号 RPM 数值。英文和简体中文资源以 `dashboard.fan_percent`、`dashboard.fan_summary` 替换 `dashboard.current_speed`。
- **版本与辅助进程迁移：** `VERSION` 和 `CFBundleShortVersionString` 从 `1.6.1` 升至 `1.7.0`；`helperVersion` 从 `"1.0"` 升至 `"1.1"`，`protocolVersion` 从 `1` 升至 `2`。新的 CPU 温度取值逻辑和最大转速上报需要更新后的辅助进程。客户端将缺失的 `fanMaxRPM` 字段视为不可用；此差异未展示自动升级辅助进程的机制。传感器访问继续使用特权 `NSXPCConnection`，`LSMinimumSystemVersion` 仍为 `15.0`。
