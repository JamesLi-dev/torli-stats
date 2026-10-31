# Torli Stats

[English README](README.md) · [使用指南](docs/user-guide.md)

Torli Stats 是一款运行在 macOS 状态栏中的本地系统监控工具，不会向服务器发送监控数据。

## 功能

- CPU 总使用率和每核心活动情况
- GPU 使用率（通过 IOKit/IORegistry 读取，具体取决于机型）
- 内存使用率
- 磁盘占用和可用空间
- 实时网络上传、下载速度
- 电池电量和充电状态
- 风扇转速和温度（授权后可用）
- 按 CPU 或内存排序的高占用进程
- 可配置的状态栏项目和监控面板模块
- 跟随系统、亮色和暗色主题
- 夜间暂停监控，默认时段为 23:30–07:00
- 连续空闲 25 分钟后可选的低干扰采样模式
- 今日输入次数、活跃时长、KPM 和 WakaTime 开发时长；历史分析由 Pro 提供
- Torli 便签：屏幕边缘便签、浮动窗口、搜索、归档、任务列表，以及 PNG/JPEG 插入、缩放、裁剪和含图片备份
- Codex 多账号额度和本地 Token 活动统计
- 自动与手动检查 GitHub Release 更新
- 可配置更新间隔、进程数量和排序方式
- 开机启动

## 下载与安装

从[最新 Release](https://github.com/JamesLi-dev/torli-stats/releases/latest) 下载 Apple Silicon（arm64）压缩包，解压后将 `TorliStats.app` 移到 `/Applications`。启动后点击状态栏项目打开面板，右键打开设置。

当前发布包采用 ad-hoc 签名，尚未配置 Developer ID 公证。macOS 可能拦截首次打开，升级后也可能要求重新授权；发布流程目前不提供 Intel 或 Universal 安装包。

## 系统要求

- macOS 15 或更高版本
- Xcode Command Line Tools（仅源码构建需要）

## 从源码运行

```bash
swift run
```

## 构建并安装 App

```bash
./build-app.sh
```

脚本会构建 Release 版本，使用配置的签名身份进行签名，将 App 安装到 `/Applications/TorliStats.app`，并自动关闭、重启正在运行的旧版本。

如果只构建而不安装或重启 App：

```bash
SKIP_INSTALL=1 ./build-app.sh
```

## 使用方式

点击状态栏中的 CPU/MEM 数值可以打开监控面板，点击面板外部即可关闭。右键点击状态栏项目，可以打开设置或退出 Torli Stats。

设置窗口支持调整外观、状态栏显示项目、更新间隔、夜间暂停监控、低干扰采样、进程显示、面板模块、输入与开发统计、传感器授权、更新检查和开机启动。设置会自动保存。

监控数据、输入聚合统计和便签保存在本机；启用 Codex、WakaTime 和更新检查时会访问对应服务。WakaTime 使用具有 `read_summaries` 权限的个人 OAuth Token，并将其保存在 macOS 钥匙串中；旧 API Key 需要手动替换。

便签数据库正文使用本地加密，图片文件和导出的备份不在该正文加密范围内。含图片备份可使用 `.stickies`；Markdown 导出需连同图片文件夹一起保存。配置、快捷键和备份操作见[使用指南](docs/user-guide.md)。

社区版包含便签与 Codex；历史输入/WakaTime 分析和邮箱验证码由 Pro 扩展提供。

## 传感器辅助进程

读取风扇转速和温度可能需要安装可选的传感器辅助进程。在设置中点击“授权读取风扇和温度”。安装辅助进程前，需要先将 App 放在“应用程序”文件夹中。

## 说明

macOS 没有稳定的公开 GPU 使用率 API。Torli Stats 会在可用时读取 IORegistry 中的 `Renderer Utilization %` 和 `Device Utilization %` 字段，并避免将同一行中的内存数值误判为 GPU 使用率。

## 开发与后续计划

本仓库提供可独立构建的社区版及 `TorliStatsCore` Swift Package。

- [架构说明](ARCHITECTURE.md)
- [开发、签名、Changelog 与发布流程](docs/development.md)
- [产品计划](TODO.md) · [便签计划](note-todo.md)
- [更新记录](CHANGELOG.md)
