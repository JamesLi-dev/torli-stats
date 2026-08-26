#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "错误：当前目录不是 Git 仓库。" >&2
    exit 1
fi

# CHANGELOG.md is generated from the other staged files, so editing it does not
# cause the same staged change to be sent to the model again. The checked-in
# CHANGELOG.md intentionally contains only the latest generated entry; older
# content is copied to the ignored .changelog-backups/ directory below.
STAGED_FILES="$(git diff --cached --name-status -- . ':(exclude)CHANGELOG.md')"
if [[ -z "$STAGED_FILES" ]]; then
    echo "错误：没有可分析的已暂存变更，请先执行 git add。" >&2
    exit 1
fi

STAGED_DIFF="$(git diff --cached --no-ext-diff --unified=80 -- . ':(exclude)CHANGELOG.md')"
MAX_DIFF_CHARS="${AI_CHANGELOG_MAX_DIFF_CHARS:-120000}"
if (( ${#STAGED_DIFF} > MAX_DIFF_CHARS )); then
    STAGED_DIFF="${STAGED_DIFF:0:MAX_DIFF_CHARS}

[Diff truncated at ${MAX_DIFF_CHARS} characters. Use the staged file list and available context; do not invent omitted details.]
"
fi

CHANGE_ID="$(printf '%s\n%s' "$STAGED_FILES" "$STAGED_DIFF" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
CHANGELOG="$ROOT/CHANGELOG.md"
if [[ -f "$CHANGELOG" ]] && grep -Fq "<!-- ai-changelog:$CHANGE_ID -->" "$CHANGELOG"; then
    echo "该批暂存变更已经生成过 Changelog：$CHANGE_ID"
    exit 0
fi

PROMPT="$(cat <<EOF
You are writing a careful, detailed changelog entry for the Torli Stats macOS menu-bar system monitor.

Analyze only the staged file list and diff below. Do not claim behavior, tests, compatibility, or user-visible changes that are not supported by the diff. Mention important implementation details, permissions, platform constraints, migration concerns, and validation results only when evidenced. Keep code identifiers, commands, and API names exact.

Return only a Markdown fragment, with no top-level title and no fenced code block, using exactly these sections:

### English
- Start with a concise user-facing summary.
- Add detailed bullets grouped by feature, fix, or internal change as appropriate.
- Include a "Validation" bullet only for checks evidenced by the diff or the provided context.

### 中文
- Provide an equally detailed Chinese version of the same changes.
- Do not translate code identifiers, commands, API names, or file paths.

The entry will be reviewed by a human before it is committed.

Staged files:
$STAGED_FILES

Staged diff:
$STAGED_DIFF
EOF
)"

run_ai() {
    if [[ -n "${AI_CHANGELOG_COMMAND:-}" ]]; then
        # Custom commands must read the prompt from stdin and write Markdown to stdout.
        printf '%s' "$PROMPT" | bash -c "$AI_CHANGELOG_COMMAND"
    elif command -v codex >/dev/null 2>&1; then
        printf '%s' "$PROMPT" | codex exec --ephemeral --sandbox read-only --cd "$ROOT" -
    elif command -v claude >/dev/null 2>&1; then
        printf '%s' "$PROMPT" | claude -p --no-session-persistence
    else
        echo "错误：未找到 codex 或 claude。可通过 AI_CHANGELOG_COMMAND 指定一个读取 stdin、输出 Markdown 的命令。" >&2
        exit 1
    fi
}

AI_OUTPUT="$(run_ai)"
if [[ -z "${AI_OUTPUT//[[:space:]]/}" ]]; then
    echo "错误：AI 没有生成 Changelog 内容。" >&2
    exit 1
fi

# Remove accidental outer Markdown fences while preserving the generated content.
AI_OUTPUT="$(printf '%s\n' "$AI_OUTPUT" | sed -e '1{/^```[[:alnum:]_-]*[[:space:]]*$/d;}' -e '${/^```[[:space:]]*$/d;}')"
ENTRY_FILE="$(mktemp)"
trap 'rm -f "$ENTRY_FILE"' EXIT
{
    printf '<!-- ai-changelog:%s -->\n' "$CHANGE_ID"
    printf '### %s\n\n' "$(date +%Y-%m-%d)"
    printf '%s\n' "$AI_OUTPUT"
} > "$ENTRY_FILE"

ARCHIVE_DIR="$ROOT/.changelog-backups"
if [[ -s "$CHANGELOG" ]]; then
    mkdir -p "$ARCHIVE_DIR"
    ARCHIVE_PATH="$ARCHIVE_DIR/$(date +%Y-%m-%d)-changelog.md"
    suffix=2
    while [[ -e "$ARCHIVE_PATH" ]]; do
        ARCHIVE_PATH="$ARCHIVE_DIR/$(date +%Y-%m-%d)-changelog-${suffix}.md"
        suffix=$((suffix + 1))
    done
    cp "$CHANGELOG" "$ARCHIVE_PATH"
    echo "已备份旧 Changelog：${ARCHIVE_PATH#$ROOT/}"
fi

python3 - "$CHANGELOG" "$ENTRY_FILE" <<'PY'
from pathlib import Path
import sys

changelog = Path(sys.argv[1])
entry = Path(sys.argv[2]).read_text().rstrip()
text = "# Changelog\n\nAll notable changes to Torli Stats are documented here.\n\n"
text += "## [Unreleased]\n\n" + entry + "\n"
changelog.write_text(text)
PY

echo "已生成 CHANGELOG.md（仅保留最新条目，变更标识：$CHANGE_ID）。请检查内容后执行："
echo "  git add CHANGELOG.md"
