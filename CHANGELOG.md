# Changelog

All notable changes to Torli Stats are documented here.

## [1.1.5] — 2026-09-02

### English
- Adds battery-aware monitoring: choose separate plugged-in and battery refresh intervals, and optionally slow high-frequency monitoring to at least 30 seconds below a chosen 10%, 20%, or 30% battery threshold.
- Confirms the public GitHub Releases endpoint is reachable for update checks.
- Refines Settings layout by keeping System below Sensors, moving Helper and protocol tags to the Sensor card header, showing sensor capabilities in a compact two-column grid, and grouping Dashboard visibility and ordering controls into one section.
- Status-bar and Dashboard ordering editors now list only enabled items. Hidden items retain their saved position and return to it when re-enabled.
- Places input-monitoring permission status beside its toggle and aligns the manual update-check action with the automatic-update toggle.

### 中文
- 新增电池感知的监控策略：可分别设置接电与电池时的刷新间隔，并可在电量低于 10%、20% 或 30% 阈值时，将高频监控自动降至至少每 30 秒一次。
- 已确认公开 GitHub Releases 更新检查接口可正常访问。
- 优化设置页布局：系统模块置于传感器下方；Helper 与协议标签移至传感器卡片头部；传感器能力使用紧凑双列网格；Dashboard 显示开关与排序合并为同一设置区域。
- 菜单栏与 Dashboard 排序编辑器现在只显示已启用项目。隐藏项目会保留已保存的位置，重新启用后恢复该位置。
- 输入监控权限状态移至输入统计开关右侧；手动检查更新按钮与自动检查更新开关同行对齐。
