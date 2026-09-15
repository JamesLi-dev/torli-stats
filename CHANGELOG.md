# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:1a93a3482b8d -->
### 2026-09-15

### English

- Adds Markdown-aware note editing and rendering, with structured block styling, safer checklist handling, and custom task-checkbox drawing while keeping note content as plain text.
- Markdown support:
  - Adds `MarkdownASTIndex` and `MarkdownBlockParser` for headings, unordered and ordered lists, task lines, nested quotes, YAML front matter, fenced and indented code, dividers, and paragraphs.
  - Uses `swift-markdown` source locations with UTF-8-to-UTF-16 conversion for `NSTextStorage` ranges.
  - `EditorStyleEngine` now styles complete Markdown blocks, hides syntax markers outside the active line, preserves inline Markdown styling, expands rescans for front matter and code-fence edits, and applies block-specific fonts, indentation, backgrounds, quote bars, and divider lines.
  - `HidingLayoutManager` draws quote, front matter, code-block, divider, and task-checkbox decorations without changing the stored source.
  - Opening YAML front matter displays the placeholder `input YAML Front Matter.`.
- Task handling:
  - Centralizes task parsing through `TaskLine.parse`.
  - `Tasks.fromMarkdown` now converts only valid line-start Markdown task prefixes, supports indentation and `[ ]`/`[x]`/`[X]`, and preserves indentation and line endings.
  - `Tasks.toMarkdown` converts only parsed task prefixes, leaving ordinary prose untouched.
  - `EditorBridge.toggleTaskLine()` inserts or removes task markers after indentation and does nothing inside code blocks.
  - Task progress, note previews, and `NotePreviewCard` now use parsed task information; `TaskCheckboxRenderer`, `TaskPreviewLine`, and related task models provide custom editor and preview rendering.
- Dependencies and licensing:
  - Adds `swift-markdown` from `https://github.com/apple/swift-markdown.git`, with `swift-markdown` and `swift-cmark` pinned to version `0.8.0` in `Package.resolved`.
  - Adds `LICENSES/Swift-CMark-COPYING.txt` and `LICENSES/Swift-Markdown-NOTICE.txt`, and updates `THIRD_PARTY_NOTICES.md`.
- Release and platform:
  - Updates `CFBundleShortVersionString` from `1.5.0` to `1.6.0`.
  - The macOS 15.0 minimum remains declared in both `Package.swift` and `Info.plist`.
  - No new macOS privacy or permission declarations are added to `Info.plist`.
- Adds `Tests/TorliStatsTests/MarkdownBlockTests.swift` and `Tests/TorliStatsTests/NoteTaskTests.swift` for Markdown block and note-task coverage.
- Migration consideration: The stored note body remains plain text and no content migration is shown. Markdown conversion semantics are now prefix-aware rather than global string replacement, so embedded checkbox-like text is no longer converted unless it matches a valid task prefix.

### 中文

- 为 Torli Stats 增加 Markdown 感知的笔记编辑与渲染能力，包含结构化块级样式、更安全的任务清单处理，以及自定义任务复选框绘制；笔记内容仍以纯文本保存。
- Markdown 支持：
  - 新增 `MarkdownASTIndex` 和 `MarkdownBlockParser`，处理标题、无序列表、有序列表、任务行、嵌套引用、YAML Front Matter、围栏代码块、缩进代码块、分隔线和普通段落。
  - 使用 `swift-markdown` 的源位置，并将 UTF-8 偏移转换为 `NSTextStorage` 所需的 UTF-16 范围。
  - `EditorStyleEngine` 现在按完整 Markdown 块执行样式处理，在非当前编辑行隐藏语法标记，保留行内 Markdown 样式，并针对 Front Matter 和代码围栏编辑扩大重新扫描范围；同时应用块级字体、缩进、背景、引用栏和分隔线样式。
  - `HidingLayoutManager` 绘制引用、Front Matter、代码块、分隔线和任务复选框装饰，不修改保存的源文本。
  - YAML Front Matter 的起始位置会显示占位文本 `input YAML Front Matter.`。
- 任务处理：
  - 通过 `TaskLine.parse` 集中任务解析逻辑。
  - `Tasks.fromMarkdown` 现在只转换行首的有效 Markdown 任务前缀，支持缩进以及 `[ ]`/`[x]`/`[X]`，并保留缩进和换行符。
  - `Tasks.toMarkdown` 只转换已解析的任务前缀，不再修改普通文本中的类似内容。
  - `EditorBridge.toggleTaskLine()` 会在缩进之后插入或移除任务标记；代码块中的行不会被切换。
  - 任务进度、笔记预览和 `NotePreviewCard` 现在使用解析后的任务信息；`TaskCheckboxRenderer`、`TaskPreviewLine` 及相关任务模型负责编辑器和预览中的自定义绘制。
- 依赖与许可证：
  - 添加 `https://github.com/apple/swift-markdown.git` 提供的 `swift-markdown`，并在 `Package.resolved` 中将 `swift-markdown` 和 `swift-cmark` 固定为 `0.8.0`。
  - 新增 `LICENSES/Swift-CMark-COPYING.txt` 和 `LICENSES/Swift-Markdown-NOTICE.txt`，并更新 `THIRD_PARTY_NOTICES.md`。
- 发布与平台：
  - 将 `CFBundleShortVersionString` 从 `1.5.0` 更新为 `1.6.0`。
  - `Package.swift` 和 `Info.plist` 中保留 macOS 15.0 最低版本要求。
  - `Info.plist` 未新增 macOS 隐私或权限声明。
- 新增 `Tests/TorliStatsTests/MarkdownBlockTests.swift` 和 `Tests/TorliStatsTests/NoteTaskTests.swift`，用于 Markdown 块和笔记任务相关覆盖。
- 迁移注意事项：现有笔记正文仍保持纯文本格式，差异中未显示内容迁移逻辑。Markdown 转换从全局字符串替换改为按任务前缀解析，因此包含类似复选框文本的普通内容只有在匹配有效任务前缀时才会被转换。
