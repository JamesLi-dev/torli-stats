# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:c953e80452c9 -->
### 2026-08-30

### English

- Added configurable display names for the default Codex account, persisted under `codexDefaultAccountName` and restored by `resetToDefaults()`. `CodexUsageView` now displays the configured name with a `Codex 账号` fallback when the value is blank.
- Updated the Codex settings UI to edit the default account’s display name and clarified that managed accounts use their display names. The existing managed-account directory and login behavior remains unchanged in the diff.
- Removed account email fallback from the status-bar tooltip; tooltip details now use the status-bar prefix.
- Added Bluetooth device classification for headphones, keyboards, trackpads, mice, game controllers, and generic devices. `BluetoothReader` now parses `Major Type:` and `Minor Type:` from `/usr/sbin/system_profiler SPBluetoothDataType` and selects a corresponding SF Symbol instead of always using `airpodspro`.
- Changed Bluetooth device titles in `BatteryRing` to a single middle-truncated line with `.help(title)` for the full name, preventing long names from creating uneven two-line layouts.
- Bumped the application version from `1.0.0` to `1.0.1` in both `VERSION` and `CFBundleShortVersionString`.
- The macOS minimum version remains `13.0`; no new permission declaration is shown in `Info.plist`.
- Marked custom Codex account short names as completed in `TODO.md`.

### 中文

- 为默认 Codex 账号增加可配置的显示名称，使用 `codexDefaultAccountName` 持久化，并由 `resetToDefaults()` 一并恢复默认值。`CodexUsageView` 在名称为空时使用 `Codex 账号` 作为回退显示。
- 更新 Codex 设置界面，可编辑默认账号的显示名称，并明确托管账号使用各自的显示名称。现有托管账号目录和登录行为在本次 diff 中未发生改变。
- 移除状态栏提示中对账号邮箱的回退显示；提示详情现在使用状态栏前缀。
- 增加蓝牙设备分类，支持耳机、键盘、触控板、鼠标、游戏控制器和通用设备。`BluetoothReader` 现在解析 `/usr/sbin/system_profiler SPBluetoothDataType` 输出中的 `Major Type:` 和 `Minor Type:`，并根据设备类型选择对应的 SF Symbol，不再统一使用 `airpodspro`。
- 将 `BatteryRing` 中的蓝牙设备名称改为单行中部截断，并通过 `.help(title)` 提供完整名称，避免过长名称造成不均匀的两行布局。
- 将应用版本从 `1.0.0` 升级到 `1.0.1`，同步更新 `VERSION` 和 `CFBundleShortVersionString`。
- macOS 最低版本仍为 `13.0`；`Info.plist` 中未显示新增权限声明。
- 在 `TODO.md` 中将自定义 Codex 账号短名称标记为已完成。
