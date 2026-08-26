# Torli Stats

[English README](README.md)

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
- 省电采样模式
- 可配置更新间隔、进程数量和排序方式
- 开机启动

## 系统要求

- macOS 13 或更高版本
- Xcode Command Line Tools

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

设置窗口支持调整外观、状态栏显示项目、更新间隔、省电模式、进程显示、面板模块、传感器授权和开机启动。设置会自动保存。

## 传感器辅助进程

读取风扇转速和温度可能需要安装可选的传感器辅助进程。在设置中点击“授权读取风扇和温度”。安装辅助进程前，需要先将 App 放在“应用程序”文件夹中。

## Changelog 工作流

可以使用已安装的 `codex` 或 `claude` CLI，根据已暂存的代码变更在本地生成详细的 Changelog：

```bash
./scripts/generate-changelog.sh
# 检查生成内容后再暂存：
git add CHANGELOG.md
```

脚本只会分析已暂存的变更，不会根据 diff 臆测未实现的功能。每次生成会让已提交的 `CHANGELOG.md` 只保留最新条目，并将旧内容备份到被 `.gitignore` 排除的 `.changelog-backups/` 目录，例如 `.changelog-backups/2026-08-25-changelog.md`。启用可选的提交前 Hook：

```bash
./scripts/setup-git-hooks.sh
AI_CHANGELOG_ON_COMMIT=1 git commit
```

GitHub Actions 会在每次 `main` 更新时构建并上传 App 压缩包，同时创建类似 `main-12` 的唯一预发布 Release。推送类似 `v0.1.0` 的版本标签时，会创建正式的 GitHub Release。为了让版本更新日志更准确，打标签前请将已检查过的 `[Unreleased]` 章节改名为 `[vX.Y.Z]`。

## 说明

macOS 没有稳定的公开 GPU 使用率 API。Torli Stats 会在可用时读取 IORegistry 中的 `Renderer Utilization %` 和 `Device Utilization %` 字段，并避免将同一行中的内存数值误判为 GPU 使用率。
