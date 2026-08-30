#!/bin/bash
set -euo pipefail

# Bump the user-facing semantic version in VERSION and Info.plist.
# Usage: ./scripts/bump-version.sh major|minor|patch

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
INFO_PLIST="$ROOT/Info.plist"
KIND="${1:-}"

if [[ ! "$KIND" =~ ^(major|minor|patch)$ ]]; then
  echo "Usage: $0 major|minor|patch" >&2
  exit 64
fi

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "VERSION must use MAJOR.MINOR.PATCH (found: $CURRENT)" >&2
  exit 65
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$KIND" in
  major) ((MAJOR += 1)); MINOR=0; PATCH=0 ;;
  minor) ((MINOR += 1)); PATCH=0 ;;
  patch) ((PATCH += 1)) ;;
esac

NEXT="$MAJOR.$MINOR.$PATCH"
printf '%s\n' "$NEXT" > "$VERSION_FILE"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT" "$INFO_PLIST"
printf 'Version bumped: %s → %s\n' "$CURRENT" "$NEXT"
