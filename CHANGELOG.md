# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:b0e6e44756be -->
### 2026-08-26

### English

- Adjusted the macOS menu-bar dashboard height dynamically according to visible modules and the configured process count, while keeping the width at `360` points and clamping the height between `160` and `760` points.
- Dashboard sizing now recalculates when `AppSettings` changes, so module visibility and process-count changes update the popover size.
- Increased the settings window’s initial and ideal height from `460` to `560` points; `SettingsView` now uses a minimum height of `520` and an ideal height of `560`.
- Added `3` as a selectable process-count option. The default process count changed from `8` to `5` for new or invalid stored values, and “恢复默认设置” now resets it to `5`. Existing stored values of `5`, `8`, `10`, and `15` remain accepted.
- Added `docs/codex-usage-multi-account-plan.md` as a planning document only; it explicitly states that multi-account support has not yet been implemented.
- The planned multi-account design is limited to locally authenticated Codex CLI accounts. It proposes separate `CODEX_HOME` directories under `~/.torli-stats-codex/<目录名>`, explicit per-process `CODEX_HOME` usage with commands such as `codex login` and `codex app-server --stdio`, and recommended `0700` permissions for the managed root and account directories.
- The plan excludes OAuth, storage or display of `access_token`, `refresh_token`, authentication headers, raw `auth.json`, and Pi Agent credentials. Removing an account is planned to remove configuration only, not its account directory or login files.

### 中文

- 调整 macOS 菜单栏面板高度：根据当前显示的模块和进程数量动态计算，同时保持宽度为 `360` 点，并将高度限制在 `160` 至 `760` 点之间。
- 当 `AppSettings` 发生变化时重新计算面板尺寸，因此模块显示状态和进程数量变化会同步更新 popover 高度。
- 设置窗口的初始高度和理想高度从 `460` 点增加到 `560` 点；`SettingsView` 的最小高度调整为 `520`，理想高度调整为 `560`。
- 增加 `3` 个进程的选项。新配置或已保存值无效时，进程数量默认值从 `8` 改为 `5`；“恢复默认设置”也会重置为 `5`。已保存的 `5`、`8`、`10`、`15` 仍然有效。
- 新增 `docs/codex-usage-multi-account-plan.md`，仅包含规划方案；文档明确说明多账号支持尚未实现。
- 该多账号方案限定为本机已登录的 Codex CLI 账号，计划将账号分别放置在 `~/.torli-stats-codex/<目录名>` 下的独立 `CODEX_HOME` 中，并通过 `codex login`、`codex app-server --stdio` 等命令为每个子进程显式设置对应的 `CODEX_HOME`；同时建议将管理根目录和账号目录设置为 `0700` 权限。
- 方案不包含 OAuth，也不保存或展示 `access_token`、`refresh_token`、认证头、原始 `auth.json` 或 Pi Agent 凭据。移除账号计划仅删除账号配置，不删除账号目录或登录文件。


<!-- ai-changelog:d6bb7b86365e -->
### 2026-08-25

### English
- Added single-account Codex usage monitoring through `codex app-server --stdio`, with usage data available in the dashboard and existing menu-bar status item.
- Added `CodexUsageClient`, `CodexUsageModels`, `CodexUsageStore`, and `CodexUsageView`:
  - Resolves Codex Home from the configured `codexHomePath`, `CODEX_HOME`, or `~/.codex`.
  - Verifies the directory and `auth.json` exist without parsing or storing token contents.
  - Finds `codex` through `PATH`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and `/usr/bin/codex`.
  - Starts `codex app-server --stdio`, performs `initialize`, then requests `account/read` and `account/rateLimits/read` using JSON-RPC over standard input/output.
  - Runs asynchronously on utility queues, drains stderr without exposing it to the UI, prevents concurrent refreshes, applies a 15-second timeout, and terminates the child process after completion.
  - Parses account identity, plan type, primary and secondary rate-limit windows, credits, reset timestamps, and clamps `usedPercent` to 0–100.
  - Preserves the previous snapshot when a refresh fails; initial failures are shown as categorized `CodexUsageError` states.
- Added a Codex dashboard card with account email, plan label, usage and remaining percentages, progress coloring, reset time, credits status, last update time, secondary-window information, loading state, error state, and manual refresh.
- Extended the existing menu-bar title instead of creating a second `NSStatusItem`:
  - Displays an account prefix derived from the email, or `C` when unavailable.
  - Displays either remaining or used percentage according to `codexStatusMetric`.
  - Uses green, orange, or red status coloring based on remaining capacity.
  - Updates the status-bar tooltip with the account prefix and current percentages.
- Added persisted settings for `showCodexCard`, `showCodexStatusItem`, `codexStatusMetric`, and `codexHomePath`. New installations default to showing Codex information, displaying remaining capacity, and automatically resolving Codex Home.
- Added Codex Home directory selection through `NSOpenPanel`, an `立即刷新` action in settings, and reset-to-default handling for all new settings keys.
- Updated the dashboard and settings layouts:
  - Increased the dashboard popover to 360×820.
  - Added hidden overlay-style small scrollbars through `ThinScrollViewConfigurator`.
  - Reduced card spacing, padding, typography, and minimum heights.
  - Made settings vertically scrollable, reorganized the settings sections, and reduced the settings window minimum and initial heights.
- Added `docs/codex-usage-single-account-plan.md`, documenting the single-local-account scope, `codex app-server` protocol, path and executable resolution, error handling, refresh lifecycle, privacy constraints, UI behavior, testing plan, acceptance criteria, and future multi-account boundaries.
- The implementation remains macOS-specific through AppKit, SwiftUI, `NSStatusItem`, `NSOpenPanel`, and `Process`; it relies on the locally installed Codex CLI and its existing authentication state rather than introducing an in-app login flow.

### 中文
- 通过 `codex app-server --stdio` 增加单账号 Codex 使用情况监控，并将数据接入 Dashboard 和现有菜单栏状态项。
- 新增 `CodexUsageClient`、`CodexUsageModels`、`CodexUsageStore` 和 `CodexUsageView`：
  - 按 `codexHomePath`、`CODEX_HOME`、`~/.codex` 的顺序解析 Codex Home。
  - 检查目录和 `auth.json` 是否存在，但不解析或保存 token 内容。
  - 按顺序从 `PATH`、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex` 和 `/usr/bin/codex` 查找 `codex`。
  - 启动 `codex app-server --stdio`，执行 `initialize`，再通过标准输入输出上的 JSON-RPC 请求 `account/read` 和 `account/rateLimits/read`。
  - 使用 utility 队列异步执行，读取并丢弃 stderr，防止并发刷新，设置 15 秒超时，并在完成后终止子进程。
  - 解析账号身份、计划类型、主次额度窗口、Credits 和重置时间，并将 `usedPercent` 限制在 0–100 范围内。
  - 刷新失败时保留上一次快照；首次失败则显示分类后的 `CodexUsageError` 状态。
- 新增 Codex Dashboard 卡片，显示账号邮箱、计划标签、用量和剩余百分比、进度颜色、重置时间、Credits 状态、更新时间、次级窗口信息、加载状态、错误状态和手动刷新按钮。
- 复用现有菜单栏标题，不创建第二个 `NSStatusItem`：
  - 根据邮箱生成账号前缀；邮箱不可用时使用 `C`。
  - 根据 `codexStatusMetric` 显示剩余量或用量。
  - 按剩余额度使用绿色、橙色或红色状态颜色。
  - 在状态栏提示中显示账号前缀及当前百分比。
- 新增并持久化 `showCodexCard`、`showCodexStatusItem`、`codexStatusMetric` 和 `codexHomePath`。新安装默认显示 Codex 信息、显示剩余量，并自动解析 Codex Home。
- 通过 `NSOpenPanel` 增加 Codex Home 目录选择、设置页中的 `立即刷新` 操作，以及新设置项的恢复默认逻辑。
- 更新 Dashboard 和设置页布局：
  - 将 Dashboard popover 调整为 360×820。
  - 通过 `ThinScrollViewConfigurator` 增加隐藏的 overlay 小号滚动条。
  - 缩小卡片间距、内边距、字号和最小高度。
  - 使设置页支持垂直滚动，重新组织设置区域，并缩小设置窗口的初始尺寸和最小尺寸。
- 新增 `docs/codex-usage-single-account-plan.md`，记录单一本地账号范围、`codex app-server` 协议、路径和可执行文件解析、错误处理、刷新生命周期、隐私约束、UI 行为、测试计划、验收标准及后续多账号边界。
- 实现仍受 macOS 平台约束，使用 AppKit、SwiftUI、`NSStatusItem`、`NSOpenPanel` 和 `Process`；依赖本机安装的 Codex CLI 及其现有认证状态，不增加应用内登录流程。
