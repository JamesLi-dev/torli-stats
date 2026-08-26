# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:84467e13e525 -->
### 2026-08-26

### English

- Changelog generation now keeps only the latest entry in the checked-in `CHANGELOG.md`, while backing up the previous non-empty file to `.changelog-backups/`.
- Added `.changelog-backups/` to `.gitignore` so local changelog history is not staged or committed.
- Backups use date-based filenames such as `2026-08-25-changelog.md`; duplicate filenames receive incrementing suffixes such as `-2`.
- Updated `scripts/generate-changelog.sh` to copy the existing changelog before replacing it, then recreate the file with the standard `# Changelog` heading, description, `## [Unreleased]` section, and newly generated entry.
- The script output now explicitly reports that only the latest entry is retained and reports the backup path.
- Updated `README.md` and `README_CN.md` to document the latest-entry workflow, local backup location, and review/staging steps.
- Existing staged-diff analysis, change identifiers, AI command selection, and Markdown output handling remain in place.

### 中文

- Changelog 生成现在只在已提交的 `CHANGELOG.md` 中保留最新条目，同时将之前的非空文件备份到 `.changelog-backups/`。
- 在 `.gitignore` 中加入 `.changelog-backups/`，避免本地 Changelog 历史被暂存或提交。
- 备份文件使用日期命名，例如 `2026-08-25-changelog.md`；文件名重复时会追加递增后缀，例如 `-2`。
- 更新 `scripts/generate-changelog.sh`：在替换现有 Changelog 前先复制备份，然后使用标准的 `# Changelog` 标题、说明文字、`## [Unreleased]` 章节和新生成的条目重新创建文件。
- 脚本输出现在会明确提示仅保留最新条目，并显示备份路径。
- 更新 `README.md` 和 `README_CN.md`，说明最新条目工作流、本地备份目录以及检查和暂存步骤。
- 现有的暂存 diff 分析、变更标识、AI 命令选择和 Markdown 输出处理逻辑保持不变。
