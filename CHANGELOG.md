# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:ac531ba9b21a -->
### 2026-08-26

### English

- Improves macOS sensor monitoring across Apple Silicon generations by adding fallback CPU cluster keys `Tp01`–`Tp16` and fan keys `F0Ac`–`F9Ac`, including cases where `discoverKeys()` does not return fan keys.
- Refines CPU temperature selection: preferred keys remain `TCMz`, `TCMb`, `TCDX`, and `TC0P`; otherwise, the hottest valid `Tp##` cluster reading is used before falling back to the median of other CPU readings.
- Broadens accepted temperature readings from `20...100` to `10...125` °C for both CPU and GPU sensors.
- Extends SMC decoding with guarded handling for short payloads and support for `ui32`. Corrects `flt ` decoding to little-endian for Apple Silicon payloads, preventing normal fan speeds and temperatures from being interpreted as invalid or near-zero values.
- Makes `install-sensor-helper.sh` wait after `launchctl bootout` detects that `local.torli.stats.helper` has stopped, polling up to 20 times at 0.25-second intervals before reinstalling and bootstrapping the launch daemon. This addresses the asynchronous removal race during helper reinstallation.
- The installer continues to place the helper at `/Library/PrivilegedHelperTools/TorliStatsHelper` and the launch daemon at `/Library/LaunchDaemons/local.torli.stats.helper.plist`, with `root:wheel` ownership and modes `755` and `644` respectively. These system-level locations and permissions require appropriate installation privileges.

### 中文

- 改进 macOS 在不同 Apple Silicon 世代上的传感器监控：新增 CPU 集群备用键 `Tp01`–`Tp16` 和风扇备用键 `F0Ac`–`F9Ac`，即使 `discoverKeys()` 未返回风扇键也可以尝试读取。
- 优化 CPU 温度选择逻辑：优先使用 `TCMz`、`TCMb`、`TCDX` 和 `TC0P`；如果这些键不可用，则使用有效 `Tp##` 集群读数中的最高温度，最后才回退到其他 CPU 读数的中位数。
- 将 CPU 和 GPU 可接受的温度范围从 `20...100` °C 扩展为 `10...125` °C。
- 增强 SMC 解码：对过短 payload 增加长度检查，新增 `ui32` 支持，并将 Apple Silicon 的 `flt ` payload 改为按 little-endian 解码，避免正常的风扇转速和温度被解析为无效值或接近零的数值。
- 让 `install-sensor-helper.sh` 在执行 `launchctl bootout` 后确认 `local.torli.stats.helper` 已停止，最多轮询 20 次、每次间隔 0.25 秒，再重新安装并 bootstrap launch daemon，以处理辅助进程异步移除导致的重装竞态。
- 安装脚本仍会将辅助进程写入 `/Library/PrivilegedHelperTools/TorliStatsHelper`，将 launch daemon 写入 `/Library/LaunchDaemons/local.torli.stats.helper.plist`，并分别设置 `root:wheel` 所有权及 `755`、`644` 权限。这些系统级路径和权限要求具备相应的安装权限。
