# Changelog

All notable changes to Torli Stats are documented here.

## [1.1.1] — 2026-09-01

<!-- ai-changelog:1c9db62fb11f -->
### 2026-09-01

### English

- Adds dashboard customization, denser layouts, improved sensor-helper diagnostics, four runner assets, and the `1.1.1` application version.

- **Dashboard customization**
  - Adds `DashboardDensity` modes: `compact`, `standard`, and `detailed`.
  - Adds configurable `DashboardModule` ordering for CPU, GPU, memory, disk, network, fan, power, Codex, and processes.
  - Adds drag-and-drop ordering in the settings window through `DashboardModuleDropDelegate`, plus a default-order reset action.
  - Persists `dashboardDensity` and `dashboardModuleOrder` in `UserDefaults`. Missing, invalid, duplicate, or incomplete saved orders are normalized by `validDashboardModuleOrder`; existing installations fall back to `.standard` and `DashboardModule.allCases`.
  - Groups metric modules into grids while rendering power, Codex, and process modules separately according to the configured order.
  - Compact mode reduces padding and estimated panel height, hides selected device and power details, limits displayed Bluetooth battery rings to four, and limits the estimated process rows to three.
  - CPU, memory, and disk values now use warning and critical colors at their corresponding usage thresholds.
  - Battery and health indicators now use severity colors; compact power mode shows compact rings instead of health and cycle-count tags.
  - Expands the settings window minimum width from `820` to `860`.

- **Sensor helper diagnostics and validation**
  - Tracks helper reachability separately from verified availability through `sensorHelperReachable`.
  - A helper is considered verified only when it is reachable, `SensorHelperInstallationStatus.inspect()` reports a valid signature, and the reported protocol matches `SensorServiceConstants.protocolVersion`.
  - Displays helper version, protocol version, signature status, per-capability reasons for fan, CPU temperature, and GPU temperature, and the latest operation diagnostic.
  - Captures `stdout` and `stderr` from `/usr/bin/osascript` operations, reports non-zero termination details, and sanitizes occurrences of `NSHomeDirectory()` to `~`.
  - Adds a “复制诊断” action that copies a diagnostic report stating that it excludes device name, serial number, and account information.
  - Sensor installation and uninstallation continue to run through `/usr/bin/osascript` with administrator privileges. Uninstallation now clears helper metadata, capability state, and diagnostics.
  - Reachable helpers with an incompatible protocol or invalid signature are surfaced as requiring reinstallation.

- **Status-bar and resources**
  - Status-bar logo tinting now applies only when `logoImage.isTemplate` is true, preserving the original colors of non-template images.
  - Adds `Resources/runner-classic-cat.png`, `Resources/runner-dojo-panda.png`, `Resources/runner-golden-retriever.png`, and `Resources/runner-wall-breaker.png`.
  - Updates the settings text from 9 to 13 built-in RunCatNeo / RunnerGallery animations.
  - `Info.plist` updates `CFBundleShortVersionString` from `1.1.0` to `1.1.1`; `LSMinimumSystemVersion` remains `13.0`.

### 中文

- 新增 Dashboard 自定义、密度布局、传感器辅助进程诊断、4 个 runner 资源，并将应用版本更新为 `1.1.1`。

- **Dashboard 自定义**
  - 新增 `DashboardDensity`：`compact`、`standard` 和 `detailed`。
  - 新增可配置的 `DashboardModule` 顺序，覆盖 CPU、GPU、内存、磁盘、网络、风扇、电源、Codex 和进程。
  - 在设置窗口中通过 `DashboardModuleDropDelegate` 支持拖放排序，并提供恢复默认顺序操作。
  - 使用 `UserDefaults` 持久化 `dashboardDensity` 和 `dashboardModuleOrder`。缺失、无效、重复或不完整的已保存顺序会由 `validDashboardModuleOrder` 规范化；已有安装在没有这些设置时回退到 `.standard` 和 `DashboardModule.allCases`。
  - 按配置顺序将指标模块组合到网格中，并单独渲染电源、Codex 和进程模块。
  - 紧凑模式会减少边距和面板高度估算，隐藏部分设备与电源详情，最多显示 4 个蓝牙电量环，并将进程高度估算限制为 3 行。
  - CPU、内存和磁盘数值现在会根据对应的警告和严重使用率阈值显示颜色。
  - 电池电量和健康度指标现在使用严重程度颜色；紧凑电源模式使用紧凑环形指标替代健康度和循环次数标签。
  - 设置窗口最小宽度从 `820` 增加到 `860`。

- **传感器辅助进程诊断与验证**
  - 通过 `sensorHelperReachable` 将辅助进程可连接状态与已验证可用状态分开记录。
  - 只有在辅助进程可连接、`SensorHelperInstallationStatus.inspect()` 报告签名有效，并且协议版本与 `SensorServiceConstants.protocolVersion` 一致时，辅助进程才会被视为已验证。
  - 设置界面显示辅助进程版本、协议版本、签名状态，以及风扇、CPU 温度和 GPU 温度各项能力的具体原因。
  - 捕获 `/usr/bin/osascript` 操作的 `stdout` 和 `stderr`，报告非零退出状态，并将 `NSHomeDirectory()` 中出现的路径替换为 `~`。
  - 新增“复制诊断”操作，复制的诊断报告明确说明不包含设备名称、序列号或账号信息。
  - 传感器安装和卸载仍通过带有管理员权限的 `/usr/bin/osascript` 执行；卸载后会清除辅助进程元数据、能力状态和诊断信息。
  - 对于可连接但协议不兼容或签名无效的辅助进程，界面会提示需要重新安装。

- **状态栏与资源**
  - 只有在 `logoImage.isTemplate` 为 `true` 时才对状态栏 Logo 应用模板着色，非模板图片会保留原始颜色。
  - 新增 `Resources/runner-classic-cat.png`、`Resources/runner-dojo-panda.png`、`Resources/runner-golden-retriever.png` 和 `Resources/runner-wall-breaker.png`。
  - 设置界面中的内置 RunCatNeo / RunnerGallery 动画数量说明从 9 种更新为 13 种。
  - `Info.plist` 将 `CFBundleShortVersionString` 从 `1.1.0` 更新为 `1.1.1`；`LSMinimumSystemVersion` 仍为 `13.0`。
