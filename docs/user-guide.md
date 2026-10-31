# Torli Stats User Guide / Torli Stats 使用指南

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

点击状态栏中的 CPU/MEM 数值可以打开 Dashboard。右键点击状态栏项目可以刷新数据、切换隐私模式、打开设置、查看应用信息或退出应用。

### 2. 快速开始

从 [Releases](https://github.com/JamesLi-dev/torli-stats/releases/latest) 下载 arm64 安装包。当前发布包采用 ad-hoc 签名，尚未配置 Developer ID 公证；macOS 可能拦截首次打开，升级后也可能要求重新授权。下载版不需要安装 Xcode。

安装步骤：

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
- 本地保留最近 365 天的每日计数；社区版展示今日数据，历史分析在 Pro 中查看

应用不读取或保存输入的文字内容，不保存字符、剪贴板内容或按键对应的文本。实现只记录符合条件的 `keyDown` 事件计数；Command、Control、导航、功能和删除等按键不会作为文本输入计入统计。统计结果以每日数量和秒数的形式保存在本机。

#### 4.2 如何授权

1. 打开 **状态栏右键菜单 > 设置 > 系统**。
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

### 5. WakaTime OAuth Token

#### 5.1 配置方法

1. 打开 **Settings > Development**。
2. 找到 WakaTime 设置区域。
3. 打开 [WakaTime 个人 OAuth 页面](https://wakatime.com/oauth)，获取具有 `read_summaries` 权限的个人 OAuth Token。
4. 将 OAuth Token 粘贴到 Torli Stats 的安全输入框。
5. 点击 **Save & Connect**，然后打开 WakaTime 开关。

启用并配置 OAuth Token 后，应用会自动同步 WakaTime 数据；当前默认同步间隔为 30 分钟。WakaTime 的历史数据还取决于 WakaTime API 返回的范围和账户权限。

旧 API Key 无法自动转换。升级后请重新填写个人 OAuth Token；保存成功后会清理 Torli 自己保存的旧 Key，编辑器插件的 API Key 不受影响。

#### 5.2 Token 存在哪里

OAuth Token 只写入 macOS Keychain，不写入 UserDefaults、普通配置文件或 Dashboard 缓存。Torli Stats 使用以下 Keychain 项目：

- Service：`local.torli.stats.wakatime`
- Account：`oauth-token`

应用删除 OAuth Token 时会删除该 Keychain 项目。请不要把 OAuth Token 提交到 Git、写进 `Info.plist`、放进源码，或粘贴到公开的诊断信息中。

#### 5.3 为什么编译更新后可能再次要求访问 Keychain

macOS Keychain 可能将某个项目的访问权限与应用的代码签名要求关联。ad-hoc 或未签名构建的签名身份不稳定；当应用被重新编译并替换后，新的二进制可能需要再次确认 Keychain 访问，或者无法访问旧构建保存的项目。

这不是 WakaTime OAuth Token 自动失效，也不代表 Token 已发送给 Torli Stats。遇到提示时，只应允许已确认来源的 Torli Stats 访问；如果新构建仍无法读取：

1. 打开 **Settings > Development**。
2. 在 WakaTime 区域删除旧 Token。
3. 重新粘贴 OAuth Token 并点击 **Save & Connect**。

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

### 8. Codex 与监控设置

在状态栏项目的右键菜单中打开“设置”。可以调整面板模块、顺序、显示密度、状态栏指标、Logo、主题和刷新策略。

Codex 支持配置多个账号及各自的 Codex Home，查看额度、重置时间和刷新状态；自动刷新有独立开关和间隔。额度请求依赖对应账号的登录状态。本地 Token 活动从已配置的 Codex Home 读取 token 计数事件，不等同于检测 CLI 进程运行时长。

手动暂停和夜间暂停会停止自动监控及 Codex/WakaTime 自动刷新，仍可手动刷新。夜间暂停默认时段为 23:30–07:00。可选的智能节能采样在连续空闲 25 分钟后降低采样频率。

社区版显示今日输入与 WakaTime 开发统计；历史分析和邮箱验证码由 Pro 扩展提供。便签和 Codex 功能属于公共核心。

### 9. 便签与图片

1. 从状态栏右键菜单启用便签，再选择“新建便签”或“全部便签”。便签相关入口已单独分组。
2. 在便签设置中调整屏幕边缘、显示屏、悬停行为、字号和快捷键。便签默认未启用；启用后的边缘位置默认为左侧。
3. 拖动展开便签的标题区域可将它分离为浮动窗口；在全部便签中搜索、归档和恢复便签。
4. 编辑正文时用 `⌘T` 在普通行、未完成任务 `☐`、已完成任务 `☑` 之间循环。正文保留文本标记，Markdown 样式不是完整富文本或完整 Markdown 渲染器。

默认全局快捷键：新建 `⌥⌘N`，全部便签 `⌥⌘A`，快速捕获 `⇧⌘Space`，归档库 `⌥⌘L`。可以在便签设置中修改；如果与其他应用冲突，请更换组合。

**插入图片**：在正文右键菜单选择插入图片，也可粘贴或拖入 PNG/JPEG。单张图片最多 20 MiB、4000 万像素；其他格式请先转换。

**缩放与裁剪**：选中图片后调整显示宽度，或拖动缩放手柄。裁剪支持自由比例和固定比例，按 Enter 确认、Esc 取消；编辑可用 `⌘Z` 撤销。裁剪生成新的图片资源，不承诺重启后保留原图的撤销历史。

### 10. 便签备份与本地数据

在全部便签窗口导入或导出。导出库包含归档便签，不只包含当前搜索或筛选结果。

| 格式 | 内容与使用方式 |
| --- | --- |
| `.stickies` | 便签备份，包含图片资源，适合迁移与恢复；当前导出为 v4，可导入 v1–v4。单份备份的图片原始数据合计上限为 200 MiB。 |
| Markdown | 保留文本标记并将图片写入相对路径的附属文件夹。分享或移动时请保留文档与图片文件夹的相对位置。 |
| 纯文本 | 图片以 `[Image]` 占位，不包含图片内容。 |

Markdown 导入只读取文档目录范围内的本地图片，不下载远程图片链接。

便签目录为 `~/Library/Application Support/TorliStats/Notes`：`notes.db` 保存数据库，`note.key` 用于解密正文，`Images` 保存图片。数据库正文使用本地加密，标题等元数据、图片文件及导出的备份不在该正文加密范围内。需要迁移时优先使用导出功能；手动备份应先退出 App，并完整保留目录，不能只拷贝数据库或删除密钥。

系统监控和输入聚合数据保留在本机；启用 Codex、WakaTime 或更新检查时会访问相应服务。有关构建、签名、升级验证和发布流程，见[开发与分发指南](development.md)。

### 11. 常见问题

**Q：授权后输入统计仍显示不可用？**

A：确认授权的是当前安装的 `/Applications/TorliStats.app`，不是旧路径下的测试副本。返回设置点击 **Recheck**，仍无效时退出并重新启动 App。

**Q：WakaTime Token 明明保存了，应用却显示未配置？**

A：先确认当前启动的 App 不是另一个构建副本。若是刚更换了签名身份，在设置中删除并重新保存 Key。

**Q：风扇权限授权成功但没有转速？**

A：检查辅助进程连接、签名和协议状态；部分 Mac 没有可读取的风扇或温度传感器。使用 **Copy Diagnostics** 获取脱敏信息。

**Q：是否可以通过脚本自动打开输入监控？**

A：不可以。macOS 不允许应用或安装脚本静默授予该隐私权限，必须由用户在系统设置中确认。

**Q：本地编译是否会上传我的输入或 Notes？**

A：Torli Stats 的输入统计、系统指标和 Notes 保存在本机。WakaTime 开启后只向 WakaTime API 请求数据；OAuth Token 仍保存在本机 Keychain。

---

## English Guide

### 1. Overview

Torli Stats is a local macOS menu-bar system monitor. CPU, GPU, memory, disk, network, battery, process, and typing statistics stay on this Mac by default; the app does not send monitoring data to a Torli Stats server.

Requirements:

- macOS 15 or later
- Xcode Command Line Tools for source builds

Click the CPU/MEM values in the menu bar to open the Dashboard. Right-click the menu-bar item to refresh data, switch privacy mode, open Settings, view app information, or quit the app.

### 2. Quick start

Download the arm64 archive from [Releases](https://github.com/JamesLi-dev/torli-stats/releases/latest). Current packages use ad-hoc signing and are not Developer ID notarized; macOS may block first launch or request permissions again after an upgrade. Downloaded builds do not require Xcode.

Installation:

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
- Local daily counts retained for 365 days; Community shows today, while Pro provides historical analysis

The app does not read or save typed text, characters, clipboard contents, or the text represented by a key. The implementation only counts eligible `keyDown` events; Command, Control, navigation, function, and deletion keys are excluded from the typing count. The resulting daily counts and durations are stored locally.

#### 4.2 How to grant it

1. Open **Menu-bar right-click menu > Settings > System**.
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

### 5. WakaTime OAuth token

#### 5.1 Configure it

1. Open **Settings > Development**.
2. Find the WakaTime section.
3. Get a personal OAuth token with `read_summaries` permission from [WakaTime OAuth](https://wakatime.com/oauth).
4. Paste it into Torli Stats’s secure input field.
5. Click **Save & Connect**, then enable WakaTime.

After an OAuth token is configured and WakaTime is enabled, the app synchronizes WakaTime data automatically. The current default interval is 30 minutes. Available history also depends on the range and permissions returned by the WakaTime API.

Legacy API keys cannot be converted automatically. Enter a personal OAuth token after upgrading. After saving it successfully, Torli removes its own saved legacy key; editor plugin API keys are unaffected.

#### 5.2 Where the token is stored

The OAuth Token is written only to the macOS Keychain, not to UserDefaults, a normal configuration file, or the Dashboard cache. Torli Stats uses this Keychain item:

- Service: `local.torli.stats.wakatime`
- Account: `oauth-token`

Removing the OAuth Token from Settings deletes that Keychain item. Never commit the token to Git, put it in `Info.plist` or source code, or include it in public diagnostic information.

#### 5.3 Why a build update may ask for Keychain access again

macOS may associate access to a Keychain item with the app’s code-signing requirement. Ad-hoc and unsigned builds do not provide a stable identity; when the app is rebuilt and replaced, the new binary may need confirmation to access the Keychain again, or may not be able to access an item saved by the previous build.

This does not mean that the WakaTime OAuth Token has expired or was sent to Torli Stats. Only allow a Torli Stats build from a source you trust to access the item. If the new build still cannot read it:

1. Open **Settings > Development**.
2. Remove the old token in the WakaTime section.
3. Paste the token again and click **Save & Connect**.

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

### 8. Codex and monitoring settings

Open Settings from the menu-bar item's right-click menu. Configure dashboard modules, order, density, menu-bar metrics, logos, appearance, and refresh policies there.

Codex supports multiple accounts and their Codex Home directories, quotas, reset times, and refresh status. Automatic refresh has its own toggle and interval. Quota requests require the account's login state. Local token activity reads token-count events from configured homes; it does not measure CLI process uptime.

Manual and night pauses stop automatic monitoring and Codex/WakaTime refreshes; manual refresh remains available. The default night window is 23:30–07:00. Optional adaptive sampling reduces frequency after 25 minutes of inactivity.

Community shows today's typing and WakaTime statistics. Historical analysis and email verification codes are Pro extensions. Notes and Codex are part of the public core.

### 9. Notes and images

1. Enable Notes from the menu-bar right-click menu, then choose New Note or All Notes. Notes actions have their own menu group.
2. Configure the screen edge, displays, hover behavior, font size, and shortcuts in Notes settings. Notes is disabled by default; its default edge is left.
3. Drag an expanded note's title area to detach it into a floating window. Search, archive, and restore notes in All Notes.
4. In the editor, `⌘T` cycles a plain line through an unchecked task `☐`, a checked task `☑`, and back to plain text. The body retains text markers; Markdown styling is not a complete rich-text editor or Markdown renderer.

Default global shortcuts: New Note `⌥⌘N`, All Notes `⌥⌘A`, Quick Capture `⇧⌘Space`, Archive Library `⌥⌘L`. Change them in Notes settings if another app uses the same combination.

**Insert an image:** use the editor's context menu, paste, or drag a PNG/JPEG into a note. Each image is limited to 20 MiB and 40 million pixels. Convert other formats first.

**Resize and crop:** select an image to adjust its displayed width or drag a resize handle. Cropping supports free and fixed aspect ratios; Enter commits and Esc cancels. Use `⌘Z` to undo edits. Cropping creates a new image resource; original-image undo history is not guaranteed after restarting.

### 10. Notes backups and local data

Import or export from All Notes. A library export includes archived notes, regardless of the current search or filter.

| Format | Contents and handling |
| --- | --- |
| `.stickies` | Bundles notes and images for backup and migration. Current exports use v4; imports support v1–v4. Total raw image data is limited to 200 MiB per archive. |
| Markdown | Preserves text markers and writes images into a relative sidecar folder. Keep the document and image folder together when moving or sharing them. |
| Plain text | Replaces images with `[Image]`; image data is not included. |

Markdown import reads local images within the document's directory only; it does not download remote image URLs.

Notes live in `~/Library/Application Support/TorliStats/Notes`: `notes.db` is the database, `note.key` decrypts note bodies, and `Images` holds image files. Body encryption does not cover titles and other metadata, image files, or exported backups. Prefer the export feature for migration. For a manual backup, quit the app and preserve the whole directory; do not copy only the database or delete its key.

System monitoring and typing aggregates stay on this Mac. Enabled Codex, WakaTime, and update checks contact their respective services. See the [development and distribution guide](development.md) for builds, signing, upgrade checks, and releases.

### 11. Troubleshooting

**Q: Typing statistics remain unavailable after authorization.**

A: Confirm that you authorized the current `/Applications/TorliStats.app`, not an older test copy at another path. Click **Recheck** and relaunch the app if needed.

**Q: WakaTime says that no token is configured even though it was saved.**

A: Make sure you did not launch another build copy. If the signing identity just changed, remove and save the token again in Settings.

**Q: Sensor authorization succeeded but no fan speed is shown.**

A: Check helper connectivity, signature, and protocol status. Some Macs expose no readable fan or temperature sensors. Use **Copy Diagnostics** for sanitized information.

**Q: Can a script automatically enable Input Monitoring?**

A: No. macOS does not allow an app or installer to silently grant this privacy permission; the user must confirm it in System Settings.

**Q: Will a local build upload my input or Notes?**

A: Torli Stats keeps typing statistics, system metrics, and Notes on this Mac. When WakaTime is enabled, it requests data only from the WakaTime API; the OAuth Token remains in the local Keychain.
