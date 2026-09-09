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
- 夜间暂停监控，默认时段为 23:30–07:00
- 连续空闲 25 分钟后可选的低干扰采样模式
- 输入与开发活动统计，并提供每日详情图表
- 内置 Torli 便签，支持搜索所有便签和查看归档
- 自动与手动检查 GitHub Release 更新
- 可配置更新间隔、进程数量和排序方式
- 开机启动

## 系统要求

- macOS 15 或更高版本
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

设置窗口支持调整外观、状态栏显示项目、更新间隔、夜间暂停监控、低干扰采样、进程显示、面板模块、输入与开发统计、传感器授权、更新检查和开机启动。设置会自动保存。

指标、输入统计和便签内容均保存在本机；WakaTime API Key 保存在 macOS 钥匙串中。

## 传感器辅助进程

读取风扇转速和温度可能需要安装可选的传感器辅助进程。在设置中点击“授权读取风扇和温度”。安装辅助进程前，需要先将 App 放在“应用程序”文件夹中。

## Changelog 工作流

可通过已安装的 `codex` 或 `claude` CLI，根据已暂存的变更在本地起草 Changelog：

```bash
git add <文件>
./scripts/generate-changelog.sh
# 检查生成内容后再暂存。
git add CHANGELOG.md
```

脚本只分析已暂存的变更；也可通过 `AI_CHANGELOG_COMMAND` 指定其他从标准输入读取、向标准输出写入内容的命令。提交前必须人工检查生成内容。脚本会写入一个 `[Unreleased]` 条目，并把旧 Changelog 备份到 `.gitignore` 排除的 `.changelog-backups/` 目录。可通过 `./scripts/setup-git-hooks.sh` 和 `AI_CHANGELOG_ON_COMMIT=1` 启用可选的提交前 Hook。

## 构建与发布自动化

`VERSION` 是用户可见的语义化版本来源，可使用以下命令升级：

```bash
./scripts/bump-version.sh major  # 1.2.3 → 2.0.0
./scripts/bump-version.sh minor  # 1.2.3 → 1.3.0
./scripts/bump-version.sh patch  # 1.2.3 → 1.2.4
```

提交生成的 `VERSION`、`Info.plist` 和已检查的 Changelog 后，将它们推送到 `main`。GitHub Actions 只在 `main` 上运行：它会构建 arm64 App 压缩包；若该版本尚未发布，则自动创建对应的 `vX.Y.Z` 标签和 GitHub Release。请不要依赖手动推送版本标签来触发工作流。

## 说明

macOS 没有稳定的公开 GPU 使用率 API。Torli Stats 会在可用时读取 IORegistry 中的 `Renderer Utilization %` 和 `Device Utilization %` 字段，并避免将同一行中的内存数值误判为 GPU 使用率。
