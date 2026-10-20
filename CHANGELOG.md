# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

### 2026-10-12

### English

Torli Stats 1.8.0 adds safe preset fan control and integrates it into the dashboard fan card.

- **Preset fan control:** The fan card offers three fixed modes: Auto, Cool, and Max. Cool targets 60% of each detected fan’s controllable minimum-to-maximum RPM range; Max targets 100%. Auto returns control to macOS.
- **Safety boundaries:** The privileged helper accepts only the fixed modes rather than arbitrary RPM values or SMC keys. If a manual-mode operation fails or the XPC connection is interrupted or invalidated, the helper restores automatic fan control.
- **Per-fan targets:** The helper reads each controllable fan’s `F…Mn` and `F…Mx` values and calculates an individual target before writing the corresponding mode and target keys. Unsupported numeric SMC formats and invalid fan ranges are rejected.
- **Dashboard refinements:** The fan card now includes compact mode controls, semantic selected-state colors, adjusted rotor sizing, centered unavailable state, consistent module gutters, and improved card footer padding. Manual modes display the requested preset percentage instead of deriving a percentage from the current RPM.
- **Helper update required:** The sensor-helper protocol advances to version 4 and helper version `1.3`; reinstall or authorize the helper from settings after updating to enable fan control.
- **Validation:** `swift test` and `./build-app.sh` completed successfully.

### 中文

Torli Stats 1.8.0 新增安全的预设风扇控制，并将控制入口整合到面板风扇卡片中。

- **预设风扇控制：** 风扇卡提供自动、降温和强冷三档。降温会以每个已识别风扇的可控最小至最大 RPM 区间的 60% 为目标；强冷为 100%。自动会恢复由 macOS 控制。
- **安全边界：** 特权辅助进程只接受固定档位，不接受任意 RPM 数值或 SMC 键。手动档位操作失败，或 XPC 连接中断、失效时，辅助进程会恢复自动风扇控制。
- **按风扇计算目标：** 辅助进程读取每个可控制风扇的 `F…Mn` 与 `F…Mx`，分别计算目标转速后再写入对应的模式与目标键。不支持的 SMC 数值格式和无效风扇区间会被拒绝。
- **面板优化：** 风扇卡加入紧凑的档位控制、具有语义的选中颜色，调整了转子尺寸和不可用状态居中效果，统一模块间距，并改善卡片底部说明的留白。手动档位显示所选预设百分比，不再由当前 RPM 换算百分比。
- **需要更新辅助进程：** 传感器辅助进程协议升级至版本 4，辅助进程版本为 `1.3`；更新后请在设置中重新安装或授权辅助进程，才能启用风扇控制。
- **验证：** 已成功执行 `swift test` 和 `./build-app.sh`。
