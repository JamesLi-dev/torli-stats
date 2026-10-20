# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

### 2026-10-20

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
