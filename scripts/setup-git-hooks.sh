#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
git config core.hooksPath .githooks

echo "已启用项目 Git hooks。"
echo "提交前自动生成 AI Changelog：AI_CHANGELOG_ON_COMMIT=1 git commit"
