# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:3333203e50eb -->
### 2026-08-27

### English
- User-facing summary: Settings now directly controls monitoring refresh intervals, provides sensor-helper management, and presents Codex remaining quota more consistently.
- Monitoring settings:
  - Centralized supported intervals in `AppSettings.supportedRefreshIntervals`; `refreshInterval` is persisted in `UserDefaults`, defaults to `3`, and is reset by `resetToDefaults()`.
  - `MetricsStore` now receives the configured interval during initialization and updates its high-frequency timer when the setting changes. Power-saving mode uses the worker interval when recalculating the timer.
- Sensor helper:
  - Added sensor status state for checking progress, fan/CPU/GPU temperature capability, and the last successful read.
  - Added “重新检测”, “重新安装”/“授权读取”, and “卸载” controls in a dedicated sensor settings section.
  - Helper installation and uninstallation run bundled scripts through `/usr/bin/osascript` with administrator privileges.
  - A missing fan RPM value is treated as an unavailable capability; it no longer stops subsequent CPU/GPU temperature reads.
  - The new `uninstall-sensor-helper.sh` is packaged into the app bundle by `build-app.sh`.
  - LaunchDaemon authorization still requires a Developer ID signed/notarized app; local builds continue to default to the ad-hoc `-` identity.
- Codex usage and account handling:
  - Codex usage progress now represents remaining quota: the progress bar and remaining percentage use green styling, while the used percentage uses secondary styling.
  - Status-bar Codex account labels and percentages now use matching column widths to keep multiple account values aligned.
  - `CodexAccountsUsageStore.synchronize()` tracks accounts included in the Dashboard or status bar and removes stores outside that active set.
- Settings layout:
  - Moved launch-at-login and reset controls into a left-column “系统” section.
  - Added a dedicated “传感器” section and synchronized the minimum heights of the two settings columns using `SettingsColumnHeightPreferenceKey`.
- Planning and repository maintenance:
  - Added `TODO.md` as the committed roadmap and ignored `/docs/` as local planning material.
  - Removed the previously committed single-account and multi-account Codex planning documents.

### 中文
- 用户可见摘要：设置页现在可直接控制监控更新间隔，并提供传感器辅助进程管理；Codex 剩余额度的展示也更加统一。
- 监控设置：
  - 通过 `AppSettings.supportedRefreshIntervals` 统一维护可选间隔；`refreshInterval` 持久化到 `UserDefaults`，默认值为 `3`，并由 `resetToDefaults()` 一并重置。
  - `MetricsStore` 初始化时接收配置的更新间隔，设置变化时更新高频指标定时器；省电模式重新计算定时器时使用 worker 内部保存的间隔。
- 传感器辅助进程：
  - 新增检测状态、风扇/CPU/GPU 温度能力以及最近一次成功读取时间等状态。
  - 在独立的传感器设置区域增加“重新检测”、“重新安装”/“授权读取”和“卸载”操作。
  - 辅助进程的安装和卸载通过 `/usr/bin/osascript` 调用打包在应用内的脚本，并请求管理员权限。
  - 缺少风扇 RPM 会被视为单项能力不可用，不再因此停止后续 CPU/GPU 温度读取。
  - `build-app.sh` 现在会将新增的 `uninstall-sensor-helper.sh` 打包到应用资源中。
  - LaunchDaemon 授权仍要求使用 Developer ID 签名并完成公证的应用；本地构建默认继续使用 ad-hoc `-` 签名身份。
- Codex 用量与账号处理：
  - Codex 用量进度现在表示剩余额度：进度条和剩余百分比使用绿色，用量百分比使用次要颜色。
  - 菜单栏中的 Codex 账号名称和百分比使用匹配的列宽，保持多个账号的数值对齐。
  - `CodexAccountsUsageStore.synchronize()` 根据账号是否显示在 Dashboard 或菜单栏来维护活动账号，并移除不在活动集合中的 Store。
- 设置界面布局：
  - 将开机启动和恢复默认设置操作移动到左列独立的“系统”区域。
  - 新增独立的“传感器”区域，并通过 `SettingsColumnHeightPreferenceKey` 同步两列设置内容的最小高度。
- 规划与仓库维护：
  - 新增作为版本内路线图的 `TODO.md`，并将 `/docs/` 标记为本地规划资料目录。
  - 删除此前提交的单账号和多账号 Codex 规划文档。
