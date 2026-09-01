# Changelog

All notable changes to Torli Stats are documented here.

## [1.1.2] — 2026-09-01

<!-- ai-changelog:5c5bac49afa7 -->
### 2026-09-01

### English
- Adds automatic GitHub release publication for version `1.1.2`, driven by the `VERSION` file.
- Release automation:
  - Runs on pushes to `main` and manual dispatches; tag pushes no longer trigger the workflow.
  - Requires `VERSION` to match `major.minor.patch`.
  - Uses `macos-14` and produces the `TorliStats-<version>-macos-arm64.zip` archive.
  - Retains `contents: write` permissions for tag and release publication, with concurrency limited per Git ref.
  - Skips publication when `v<version>` already has a GitHub Release.
  - Creates and pushes an annotated version tag when needed. If an existing tag points to a different commit, publication is refused.
  - Extracts release notes from the matching `CHANGELOG.md` version section, or uses GitHub-generated notes when that section is empty. It no longer falls back to `## [Unreleased]`.
- Updates `CFBundleShortVersionString` and `VERSION` from `1.1.1` to `1.1.2`. `LSMinimumSystemVersion` remains `13.0`; the release archive is explicitly Apple Silicon (`macos-arm64`).
- Adds update checking through `AppUpdateChecker`:
  - Queries GitHub’s latest-release API endpoint with a 12-second timeout, `User-Agent`, and `Accept: application/vnd.github+json` headers.
  - Checks automatically at launch when `automaticUpdateChecks` is enabled, with a 24-hour minimum interval, and also supports manual checks from Settings.
  - Compares semantic version components and reports `upToDate`, `available`, or `failed` status.
  - Presents an update alert once per discovered version and opens the release `html_url` when the user chooses “查看下载”.
  - Persists the `automaticUpdateChecks` setting in `UserDefaults`; existing installations default to enabled, and reset-to-defaults restores it to enabled.
- Improves Codex usage refresh handling:
  - `CodexUsageClient.fetch` now returns a `CodexUsageRequest` that can cancel an attached `CodexServerSession` and its `codex app-server --stdio` process.
  - Retryable failures (`timeout`, `networkUnavailable`, `processLaunchFailed`, and `processExited`) retry at most twice, after 3 seconds and 10 seconds. Manual refresh cancels a pending retry.
  - Adds `CodexUsageState.retrying`, preserving the previous snapshot while displaying the retry reason, countdown, and attempt number.
  - Marks snapshots older than 15 minutes as stale. Stale dashboard data displays a warning; status-bar Codex labels receive a `!` suffix and orange percentage text.

### 中文
- 新增由 `VERSION` 驱动的 GitHub 自动发布流程，当前版本更新为 `1.1.2`。
- 发布自动化：
  - 工作流在推送到 `main` 或手动触发时运行；推送 tag 不再触发该工作流。
  - 要求 `VERSION` 符合 `major.minor.patch` 格式。
  - 使用 `macos-14` 构建，并生成 `TorliStats-<version>-macos-arm64.zip`。
  - 保留用于发布 tag 和 Release 的 `contents: write` 权限，并按 Git ref 设置并发控制。
  - 当 `v<version>` 已存在 GitHub Release 时跳过发布。
  - 必要时创建并推送带注释的版本 tag；如果已有 tag 指向其他 commit，则拒绝发布。
  - 从匹配版本的 `CHANGELOG.md` 小节提取发布说明；该小节为空时使用 GitHub 自动生成的说明，不再回退到 `## [Unreleased]`。
- 将 `CFBundleShortVersionString` 和 `VERSION` 从 `1.1.1` 更新为 `1.1.2`。`LSMinimumSystemVersion` 仍为 `13.0`；发布归档明确面向 Apple Silicon（`macos-arm64`）。
- 新增 `AppUpdateChecker` 更新检查：
  - 通过 GitHub latest-release API endpoint 检查更新，设置 12 秒超时，并发送 `User-Agent` 和 `Accept: application/vnd.github+json` 请求头。
  - `automaticUpdateChecks` 启用时在应用启动时检查，最短检查间隔为 24 小时；设置页也支持手动检查。
  - 按 semantic version 的数值组件比较版本，并报告 `upToDate`、`available` 或 `failed` 状态。
  - 每个发现的版本只显示一次更新提示；用户选择“查看下载”后打开 Release 的 `html_url`。
  - 通过 `UserDefaults` 持久化 `automaticUpdateChecks`；已有安装在没有该配置时默认启用，恢复默认设置也会将其设为启用。
- 改进 Codex 使用量刷新处理：
  - `CodexUsageClient.fetch` 现在返回可取消的 `CodexUsageRequest`，能够取消已连接的 `CodexServerSession` 及其 `codex app-server --stdio` 进程。
  - `timeout`、`networkUnavailable`、`processLaunchFailed` 和 `processExited` 等可重试错误最多重试两次，间隔分别为 3 秒和 10 秒；手动刷新会取消等待中的重试。
  - 新增 `CodexUsageState.retrying`，在重试期间保留上一次快照，并显示失败原因、倒计时和重试次数。
  - `fetchedAt` 超过 15 分钟的快照会被标记为过期。仪表盘显示过期提示；状态栏中的 Codex 标签增加 `!` 后缀，百分比改为橙色。
