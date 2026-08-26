# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:84467e13e525 -->
### 2026-08-26

### English

- Added multi-account Codex usage support with the default `~/.codex` account plus independently logged-in profiles under `~/.torli-stats-codex/<name>`.
- Added per-account Codex Home configuration, terminal-based `codex login`, dashboard visibility, status-bar inclusion, account naming, re-login, and configuration-only removal without deleting local authentication files.
- Added per-account background refresh and isolated loading/error states while continuing to avoid reading, storing, or logging access and refresh tokens.
- Added menu-bar metric group ordering for System (CPU / memory), Network (download / upload), and Codex, while keeping CPU/memory and download/upload bound as single groups.
- Added compact and stacked System status-bar styles, with aligned CPU/memory labels and percentages, and Codex display modes for the default account, lowest remaining capacity, or each account.
- Made the dashboard Codex section support multiple account rows; simplified each row by moving reset and update information into the header, combining daily and weekly quota details, and removing secondary-window and Credits noise.
- Made the status-bar popover size itself from the enabled dashboard modules and process count, removing the fixed-height bottom gap and visible scrolling.
- Reorganized settings into independent columns, aligned the settings cards, moved Codex status-bar controls into Appearance and Status Bar, and tightened spacing and sizing throughout.
- Changelog generation now keeps only the latest entry in the checked-in `CHANGELOG.md`, while backing up the previous non-empty file to `.changelog-backups/`.
- Added `.changelog-backups/` to `.gitignore` so local changelog history is not staged or committed.
- Backups use date-based filenames such as `2026-08-25-changelog.md`; duplicate filenames receive incrementing suffixes such as `-2`.
- Updated `scripts/generate-changelog.sh` to copy the existing changelog before replacing it, then recreate the file with the standard `# Changelog` heading, description, `## [Unreleased]` section, and newly generated entry.
- The script output now explicitly reports that only the latest entry is retained and reports the backup path.
- Updated `README.md` and `README_CN.md` to document the latest-entry workflow, local backup location, and review/staging steps.
- Existing staged-diff analysis, change identifiers, AI command selection, and Markdown output handling remain in place.

### 中文

- 增加 Codex 多账号用量支持：默认账号继续使用 `~/.codex`，后续账号使用 `~/.torli-stats-codex/<名称>` 下独立登录的 Codex Home。
- 增加账号级 Codex Home 配置、终端 `codex login`、Dashboard 显示、状态栏参与、账号命名、重新登录和仅移除配置；不会删除本地认证文件。
- 增加账号级后台刷新及独立的加载/错误状态，并继续避免读取、保存或记录 access token 和 refresh token。
- 增加菜单栏指标组排序：系统（CPU / 内存）、网络（下载 / 上传）和 Codex；CPU/内存、下载/上传始终分别作为一个整体。
- 增加系统状态栏的紧凑/分栏样式，保证 CPU/内存标签和百分比对齐；Codex 支持默认账号、最低剩余量和逐账号三种显示模式。
- Dashboard 的 Codex 区域支持多个账号，并简化账号行：更新时间靠近刷新按钮，日/周额度共用信息行，移除短窗口和 Credits 展示。
- 菜单栏展开面板根据已启用模块和进程数量自适应高度，去除固定底部空白和可见滚动。
- 重组设置页独立左右列，对齐设置卡片，将 Codex 状态栏设置移入“外观与状态栏”，并统一优化间距和尺寸。
- Changelog 生成现在只在已提交的 `CHANGELOG.md` 中保留最新条目，同时将之前的非空文件备份到 `.changelog-backups/`。
- 在 `.gitignore` 中加入 `.changelog-backups/`，避免本地 Changelog 历史被暂存或提交。
- 备份文件使用日期命名，例如 `2026-08-25-changelog.md`；文件名重复时会追加递增后缀，例如 `-2`。
- 更新 `scripts/generate-changelog.sh`：在替换现有 Changelog 前先复制备份，然后使用标准的 `# Changelog` 标题、说明文字、`## [Unreleased]` 章节和新生成的条目重新创建文件。
- 脚本输出现在会明确提示仅保留最新条目，并显示备份路径。
- 更新 `README.md` 和 `README_CN.md`，说明最新条目工作流、本地备份目录以及检查和暂存步骤。
- 现有的暂存 diff 分析、变更标识、AI 命令选择和 Markdown 输出处理逻辑保持不变。
