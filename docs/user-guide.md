# Torli Stats User & Developer Guide / Torli Stats 用户与开发者说明书

> This guide is bilingual. The Chinese section comes first, followed by the English version.
>
> 本说明书为中英文对照版本，先中文、后英文。

---

## 中文说明

### 1. 产品简介

Torli Stats 是一个运行在 macOS 状态栏中的本地系统监控工具。CPU、GPU、内存、磁盘、网络、电池、进程和输入统计默认保存在本机；应用不会把这些监控数据发送到 Torli Stats 服务器。

系统要求：

- macOS 15 或更高版本
- 从源码构建需要 Xcode Command Line Tools

点击状态栏中的 CPU/MEM 数值可以打开 Dashboard。右键点击状态栏项目可以刷新数据、切换隐私模式、打开设置、查看诊断信息或退出应用。

### 2. 快速开始

普通用户建议使用经过稳定签名和公证的发布版：

1. 将 `TorliStats.app` 放到 `/Applications`。
2. 启动应用。
3. 打开设置，根据需要启用输入统计、WakaTime 和传感器。
4. 第一次授权后，退出并重新打开应用，确认 Dashboard 和状态栏数据正常。

从源码构建：

```bash
./build-app.sh
```

这个脚本默认使用临时的 ad-hoc 签名（`-`），并将 App 安装到 `/Applications/TorliStats.app` 后重启它。也可以只构建、不安装：

```bash
SKIP_INSTALL=1 ./build-app.sh
```

### 3. 权限和密钥总览

| 功能 | macOS 机制 | 用户是否需要确认 | 开发者能否绕过 |
| --- | --- | --- | --- |
| 输入活动统计 | Input Monitoring / ListenEvent | 是 | 否。只能由用户在系统设置中授权 |
| WakaTime | macOS Keychain 访问 | 可能需要确认 | 否。开发者只能保持稳定的签名身份 |
| 风扇和温度 | 管理员权限安装特权辅助进程 | 是 | 否。必须由用户确认管理员授权 |
| 开机启动 | `SMAppService` | 由系统管理 | 不能绕过签名和系统限制 |

这里最重要的一点是：**开发者不能在 App 内自动打开 Input Monitoring，也不能绕过 Keychain 或管理员授权。** 开发者能做的是使用稳定的 Bundle ID、稳定的开发者签名和正确的发布流程，让 macOS 在升级时识别为同一个应用。

### 4. 输入监控权限

#### 4.1 Torli Stats 使用它做什么

启用输入统计后，Torli Stats 使用 macOS 的 listen-only `CGEventTap` 监听键盘事件，用于计算：

- 当天按键数量
- 活跃输入时间
- 最近一分钟的 KPM
- 最近 365 天的每日统计

应用不读取或保存输入的文字内容，不保存字符、剪贴板内容或按键对应的文本。实现只记录符合条件的 `keyDown` 事件计数；Command、Control、导航、功能和删除等按键不会作为文本输入计入统计。统计结果以每日数量和秒数的形式保存在本机。

#### 4.2 如何授权

1. 打开 **Torli Stats > Settings > System**。
2. 打开 **Enable Typing Statistics**。
3. 点击 **Open Input Monitoring Settings**，或者在系统设置中进入：
   **System Settings > Privacy & Security > Input Monitoring**。
4. 打开 **Torli Stats** 的开关。
5. 返回 Torli Stats，点击 **Recheck**；必要时退出并重新启动应用。

如果 Dashboard 显示“需要输入监控权限”，可以直接点击空状态右侧的跳转按钮。

#### 4.3 为什么每次编译更新都可能要求重新授权

Input Monitoring 不是按应用显示名称授权，而是由 macOS 根据应用的代码签名身份和系统隐私数据库管理。下面这些情况会让 macOS 把新版本视为不同的应用：

- 使用 ad-hoc 签名或未签名的本地构建；
- 每次编译生成不同的代码签名内容；
- 在本地构建版、测试版和发布版之间来回替换；
- 修改 Bundle ID、Team ID 或签名证书；
- 手动重置 TCC/隐私权限，或系统安全策略要求重新确认。

因此，**版本号本身通常不是问题，签名身份变化才是主要原因。** 对开发者来说，使用同一个 Bundle ID、同一个 Apple Developer Team 和稳定的 Developer ID 签名发布，通常可以显著减少升级后的重复授权；但 macOS 仍可能在签名身份变化、系统重置或安全策略变化后再次要求确认，应用无法保证永远不弹窗。

### 5. WakaTime API Key

#### 5.1 配置方法

1. 打开 **Settings > Development**。
2. 找到 WakaTime 设置区域。
3. 在 WakaTime 网站的账户设置中生成或复制 API Key。
4. 将 API Key 粘贴到 Torli Stats 的安全输入框。
5. 点击 **Save & Connect**，然后打开 WakaTime 开关。

启用并配置 Key 后，应用会自动同步 WakaTime 数据；当前默认同步间隔为 30 分钟。WakaTime 的历史数据还取决于 WakaTime API 返回的范围和账户权限。

#### 5.2 Key 存在哪里

API Key 只写入 macOS Keychain，不写入 UserDefaults、普通配置文件或 Dashboard 缓存。Torli Stats 使用以下 Keychain 项目：

- Service：`local.torli.stats.wakatime`
- Account：`api-key`

应用删除 API Key 时会删除该 Keychain 项目。请不要把 API Key 提交到 Git、写进 `Info.plist`、放进源码，或粘贴到公开的诊断信息中。

#### 5.3 为什么编译更新后可能再次要求访问 Keychain

macOS Keychain 可能将某个项目的访问权限与应用的代码签名要求关联。ad-hoc 或未签名构建的签名身份不稳定；当应用被重新编译并替换后，新的二进制可能需要再次确认 Keychain 访问，或者无法访问旧构建保存的项目。

这不是 WakaTime API Key 自动失效，也不代表 Key 已发送给 Torli Stats。遇到提示时，只应允许已确认来源的 Torli Stats 访问；如果新构建仍无法读取：

1. 打开 **Settings > Development**。
2. 在 WakaTime 区域删除旧 Key。
3. 重新粘贴 API Key 并点击 **Save & Connect**。

要避免在开发过程中反复遇到这个问题，应使用稳定的 Developer ID 签名，不要在同一个安装位置混用 ad-hoc 构建和发布构建。

### 6. 风扇和温度传感器

风扇转速和温度读取通过可选的特权辅助进程完成。辅助进程不是为了收集数据到服务器，而是为了在单独的高权限进程中读取 AppleSMC/IOKit 暴露的传感器信息。

#### 6.1 安装和授权

1. 确认 App 位于 `/Applications/TorliStats.app`。
2. 打开 **Settings > Monitoring**。
3. 点击 **Authorize Fan and Temperature Access**。
4. 在 macOS 管理员确认框中输入密码。
5. 安装完成后点击 **Recheck**。

辅助进程的安装位置和服务名称为：

- 程序：`/Library/PrivilegedHelperTools/TorliStatsHelper`
- LaunchDaemon：`/Library/LaunchDaemons/local.torli.stats.helper.plist`
- Mach service：`local.torli.stats.sensor`

设置页面会验证辅助进程是否可连接、签名是否有效以及协议版本是否兼容。也可以点击 **Copy Diagnostics** 复制脱敏诊断信息。

#### 6.2 为什么需要 Developer ID

当前安装脚本通过管理员权限安装系统级 LaunchDaemon。`build-app.sh` 中的默认 `-` 仅适合本地开发；系统级辅助进程的正式安装和分发需要 Developer ID 签名，并应使用经过公证的发布包。

如果传感器显示“辅助进程需要重新安装”或“签名验证失败”：

1. 确认使用的是同一来源的完整 App。
2. 在设置中点击 **Reinstall**。
3. 重新确认管理员权限。
4. 点击 **Recheck**。
5. 如果仍失败，复制诊断信息。

并不是所有 Mac 都会暴露风扇、CPU 温度或 GPU 温度传感器。辅助进程正常运行并不代表每一项传感器都一定可用。

### 7. 开机启动

打开 **Settings > System > Launch at Login** 即可启用开机启动。该功能使用 macOS `SMAppService`，从 `swift run` 启动的未打包或未签名程序可能无法注册。遇到注册失败时，应使用安装在 `/Applications` 中的签名 App。

### 8. 开发者发布指南

#### 8.1 必须保持稳定的身份

发布和升级时请保持：

- `CFBundleIdentifier` 不变，目前是 `local.torli.stats`；
- 使用同一个 Apple Developer Team；
- 使用稳定的 Developer ID Application 证书；
- App 和内置的 `TorliStatsHelper` 使用一致、可验证的签名；
- 不要让用户在同一个路径混用 ad-hoc、本地调试和正式发布版本；
- 版本升级只改变版本号和构建内容，不随意更换 Bundle ID 或签名主体。

#### 8.2 使用 Developer ID 构建

在已经安装 Developer ID Application 证书的机器上，可以将签名身份传给当前构建脚本：

```bash
security find-identity -v -p codesigning

CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./build-app.sh
```

当前脚本默认是 ad-hoc 签名：

```bash
./build-app.sh
# 等价于使用 CODE_SIGN_IDENTITY=-
```

这适合本地开发和 UI 调试，但不适合作为需要长期保留 TCC/Keychain 身份的正式更新渠道。

#### 8.3 发布前检查

正式发布前至少应完成：

```bash
codesign --verify --deep --strict --verbose=2 TorliStats.app
spctl --assess --type execute --verbose=4 TorliStats.app
plutil -lint TorliStats.app/Contents/Info.plist
```

还应在干净用户账户或测试 Mac 上验证以下升级路径：

1. 安装旧的 Developer ID 版本。
2. 授予 Input Monitoring 权限并保存 WakaTime Key。
3. 安装新的 Developer ID 版本覆盖旧版本。
4. 确认输入统计仍能工作，且 WakaTime Key 不需要重新录入。
5. 单独测试传感器辅助进程的重新安装和版本升级。

当前仓库的 `build-app.sh` 负责构建、复制资源、签名和本地安装；正式的 Developer ID 证书管理、Hardened Runtime、notarization、stapling 和发布包上传仍属于发行环境配置的一部分，不能由用户授权替代。

### 9. 常见问题

**Q：授权后输入统计仍显示不可用？**

A：确认授权的是当前安装的 `/Applications/TorliStats.app`，不是旧路径下的测试副本。返回设置点击 **Recheck**，仍无效时退出并重新启动 App。

**Q：WakaTime Key 明明保存了，应用却显示未配置？**

A：先确认当前启动的 App 不是另一个构建副本。若是刚更换了签名身份，在设置中删除并重新保存 Key。

**Q：风扇权限授权成功但没有转速？**

A：检查辅助进程连接、签名和协议状态；部分 Mac 没有可读取的风扇或温度传感器。使用 **Copy Diagnostics** 获取脱敏信息。

**Q：是否可以通过脚本自动打开输入监控？**

A：不可以。macOS 不允许应用或安装脚本静默授予该隐私权限，必须由用户在系统设置中确认。

**Q：本地编译是否会上传我的输入或 Notes？**

A：Torli Stats 的输入统计、系统指标和 Notes 保存在本机。WakaTime 开启后只向 WakaTime API 请求数据；API Key 仍保存在本机 Keychain。

---

## English Guide

### 1. Overview

Torli Stats is a local macOS menu-bar system monitor. CPU, GPU, memory, disk, network, battery, process, and typing statistics stay on this Mac by default; the app does not send monitoring data to a Torli Stats server.

Requirements:

- macOS 15 or later
- Xcode Command Line Tools for source builds

Click the CPU/MEM values in the menu bar to open the Dashboard. Right-click the menu-bar item to refresh data, switch privacy mode, open Settings, copy diagnostic information, or quit the app.

### 2. Quick start

For regular use, install a release that has a stable signature and has been notarized:

1. Move `TorliStats.app` to `/Applications`.
2. Launch the app.
3. Open Settings and enable typing statistics, WakaTime, or sensors as needed.
4. After the first authorization, quit and relaunch the app to confirm that the Dashboard and menu-bar data work normally.

Build from source:

```bash
./build-app.sh
```

The script defaults to an ad-hoc signature (`-`) and installs the app to `/Applications/TorliStats.app`, then restarts it. To build without installing:

```bash
SKIP_INSTALL=1 ./build-app.sh
```

### 3. Permission and credential overview

| Feature | macOS mechanism | Does the user confirm it? | Can the developer bypass it? |
| --- | --- | --- | --- |
| Typing activity | Input Monitoring / ListenEvent | Yes | No. The user must grant it in System Settings |
| WakaTime | macOS Keychain access | May require confirmation | No. The developer can only keep the signing identity stable |
| Fan and temperature | Admin-authorized privileged helper | Yes | No. The user must approve the administrator prompt |
| Launch at login | `SMAppService` | Managed by the system | No; signing and system restrictions still apply |

The key point is: **an app cannot silently turn on Input Monitoring or bypass Keychain and administrator authorization.** A developer can keep the Bundle ID, Apple Developer identity, and release process stable so macOS can recognize an upgrade as the same app.

### 4. Input Monitoring

#### 4.1 What Torli Stats uses it for

When typing statistics are enabled, Torli Stats uses macOS’s listen-only `CGEventTap` to calculate:

- Today’s key count
- Active typing time
- Recent one-minute KPM
- Daily statistics for the most recent 365 days

The app does not read or save typed text, characters, clipboard contents, or the text represented by a key. The implementation only counts eligible `keyDown` events; Command, Control, navigation, function, and deletion keys are excluded from the typing count. The resulting daily counts and durations are stored locally.

#### 4.2 How to grant it

1. Open **Torli Stats > Settings > System**.
2. Turn on **Enable Typing Statistics**.
3. Click **Open Input Monitoring Settings**, or open:
   **System Settings > Privacy & Security > Input Monitoring**.
4. Enable **Torli Stats**.
5. Return to Torli Stats and click **Recheck**; relaunch the app if necessary.

If the Dashboard shows that Input Monitoring is required, use the action button on the empty state to open the relevant settings page.

#### 4.3 Why every source build may ask again

Input Monitoring is not granted based only on the app’s display name. macOS manages it through the app’s code-signing identity and the system privacy database. macOS may treat a new build as a different app when:

- the build is ad-hoc signed or unsigned;
- each local build has different signed code;
- local, test, and release builds are repeatedly swapped;
- the Bundle ID, Team ID, or signing certificate changes;
- TCC/privacy permissions are reset, or a security policy requires confirmation again.

Therefore, **the version number is usually not the root cause; the changing signing identity is.** For developers, using the same Bundle ID, Apple Developer Team, and stable Developer ID signature generally improves permission continuity across upgrades. macOS still owns the permission and may ask again after an identity change, a system reset, or a security-policy change; the app cannot guarantee that the prompt will never return.

### 5. WakaTime API key

#### 5.1 Configure it

1. Open **Settings > Development**.
2. Find the WakaTime section.
3. Generate or copy an API Key from your WakaTime account settings.
4. Paste it into Torli Stats’s secure input field.
5. Click **Save & Connect**, then enable WakaTime.

After a key is configured and WakaTime is enabled, the app synchronizes WakaTime data automatically. The current default interval is 30 minutes. Available history also depends on the range and permissions returned by the WakaTime API.

#### 5.2 Where the key is stored

The API Key is written only to the macOS Keychain, not to UserDefaults, a normal configuration file, or the Dashboard cache. Torli Stats uses this Keychain item:

- Service: `local.torli.stats.wakatime`
- Account: `api-key`

Removing the API Key from Settings deletes that Keychain item. Never commit the key to Git, put it in `Info.plist` or source code, or include it in public diagnostic information.

#### 5.3 Why a build update may ask for Keychain access again

macOS may associate access to a Keychain item with the app’s code-signing requirement. Ad-hoc and unsigned builds do not provide a stable identity; when the app is rebuilt and replaced, the new binary may need confirmation to access the Keychain again, or may not be able to access an item saved by the previous build.

This does not mean that the WakaTime API Key has expired or was sent to Torli Stats. Only allow a Torli Stats build from a source you trust to access the item. If the new build still cannot read it:

1. Open **Settings > Development**.
2. Remove the old key in the WakaTime section.
3. Paste the key again and click **Save & Connect**.

To avoid repeated prompts during development, use a stable Developer ID signature and do not mix ad-hoc and release builds at the same install path.

### 6. Fan and temperature sensors

Fan and temperature readings are provided through an optional privileged helper. The helper is not used to send data to a server; it reads sensor information exposed by AppleSMC/IOKit from a separate process with the required privileges.

#### 6.1 Install and authorize

1. Make sure the app is at `/Applications/TorliStats.app`.
2. Open **Settings > Monitoring**.
3. Click **Authorize Fan and Temperature Access**.
4. Confirm the administrator prompt.
5. Click **Recheck** after installation completes.

The helper is installed and registered at:

- Program: `/Library/PrivilegedHelperTools/TorliStatsHelper`
- LaunchDaemon: `/Library/LaunchDaemons/local.torli.stats.helper.plist`
- Mach service: `local.torli.stats.sensor`

Settings checks helper connectivity, signature validity, and protocol compatibility. **Copy Diagnostics** copies a sanitized diagnostic report.

#### 6.2 Why Developer ID matters

The current installer uses administrator privileges to install a system-level LaunchDaemon. The default `-` in `build-app.sh` is intended for local development; formal installation and distribution of the privileged helper require a Developer ID-signed app and should use a notarized release package.

If the sensor section says that the helper needs to be reinstalled or that signature verification failed:

1. Confirm that you are using the complete app from one trusted source.
2. Click **Reinstall** in Settings.
3. Confirm administrator authorization again.
4. Click **Recheck**.
5. Copy diagnostics if the problem remains.

Not every Mac exposes readable fan, CPU-temperature, or GPU-temperature sensors. A running helper does not guarantee that every sensor will be available.

### 7. Launch at login

Enable **Settings > System > Launch at Login** to use macOS `SMAppService`. An unbundled or unsigned executable launched with `swift run` may not be able to register. If registration fails, use the signed app installed in `/Applications`.

### 8. Developer distribution guide

#### 8.1 Keep the identity stable

For release and upgrade continuity, keep the following unchanged:

- `CFBundleIdentifier`, currently `local.torli.stats`;
- the Apple Developer Team;
- the Developer ID Application certificate;
- a consistent, verifiable signature for both the app and the embedded `TorliStatsHelper`;
- the installation source at a given path; do not mix ad-hoc, debug, and release builds;
- the identity while changing only the version and build contents for an upgrade.

#### 8.2 Build with Developer ID

On a Mac with a Developer ID Application certificate installed, pass the signing identity to the current build script:

```bash
security find-identity -v -p codesigning

CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./build-app.sh
```

The current script defaults to ad-hoc signing:

```bash
./build-app.sh
# equivalent to CODE_SIGN_IDENTITY=-
```

That is suitable for local development and UI debugging, but not as a long-term update channel that must preserve TCC and Keychain identity.

#### 8.3 Pre-release checks

At minimum, verify the signed app before release:

```bash
codesign --verify --deep --strict --verbose=2 TorliStats.app
spctl --assess --type execute --verbose=4 TorliStats.app
plutil -lint TorliStats.app/Contents/Info.plist
```

Also test this upgrade path on a clean user account or test Mac:

1. Install the previous Developer ID build.
2. Grant Input Monitoring and save a WakaTime Key.
3. Install the new Developer ID build over the previous one.
4. Confirm that typing statistics still work and the WakaTime key does not need to be entered again.
5. Test sensor-helper reinstallation and upgrade separately.

The repository’s current `build-app.sh` builds the app, copies resources, signs it, and can install it locally. Developer ID certificate management, Hardened Runtime, notarization, stapling, and release-upload configuration remain part of the distribution environment; user authorization cannot replace them.

### 9. Troubleshooting

**Q: Typing statistics remain unavailable after authorization.**

A: Confirm that you authorized the current `/Applications/TorliStats.app`, not an older test copy at another path. Click **Recheck** and relaunch the app if needed.

**Q: WakaTime says that no key is configured even though it was saved.**

A: Make sure you did not launch another build copy. If the signing identity just changed, remove and save the key again in Settings.

**Q: Sensor authorization succeeded but no fan speed is shown.**

A: Check helper connectivity, signature, and protocol status. Some Macs expose no readable fan or temperature sensors. Use **Copy Diagnostics** for sanitized information.

**Q: Can a script automatically enable Input Monitoring?**

A: No. macOS does not allow an app or installer to silently grant this privacy permission; the user must confirm it in System Settings.

**Q: Will a local build upload my input or Notes?**

A: Torli Stats keeps typing statistics, system metrics, and Notes on this Mac. When WakaTime is enabled, it requests data only from the WakaTime API; the API Key remains in the local Keychain.
