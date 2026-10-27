#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="${TORLI_PACKAGE_ROOT:-$ROOT}"
PRODUCT="${TORLI_PRODUCT:-TorliStats}"
APP_NAME="${TORLI_APP_NAME:-TorliStats}"
[[ "$PRODUCT" =~ ^[A-Za-z0-9]+$ && "$APP_NAME" =~ ^[A-Za-z0-9]+$ ]] || exit 1
APP="$PACKAGE_ROOT/$APP_NAME.app"
VERSION="$(tr -d '[:space:]' < "$PACKAGE_ROOT/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$PACKAGE_ROOT" rev-list --count HEAD)}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must use MAJOR.MINOR.PATCH (found: $VERSION)" >&2
  exit 1
fi

swift build --package-path "$PACKAGE_ROOT" -c release --product "$PRODUCT"
BIN_DIR="$(swift build --package-path "$PACKAGE_ROOT" -c release --show-bin-path)"
swift build --package-path "$ROOT" -c release --product TorliStatsHelper
HELPER_BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses" \
  "$APP/Contents/Library/LaunchDaemons" \
  "$APP/Contents/Library/LaunchServices"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp "$HELPER_BIN_DIR/TorliStatsHelper" \
  "$APP/Contents/Library/LaunchServices/TorliStatsHelper"
cp "$PACKAGE_ROOT/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM library resources must travel with either application entry point.
for resource_bundle in "$BIN_DIR"/*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  ditto "$resource_bundle" "$APP/Contents/Resources/$(basename "$resource_bundle")"
done
for runner_asset in "$ROOT"/Resources/runner-*.png; do
  cp "$runner_asset" "$APP/Contents/Resources/$(basename "$runner_asset")"
done
cp -R "$ROOT"/Sources/TorliStats/NotesResources/. "$APP/Contents/Resources/"
cp -R "$ROOT"/Sources/TorliStats/StatsResources/. "$APP/Contents/Resources/"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/LICENSES/Apache-2.0.txt" "$APP/Contents/Resources/Licenses/Apache-2.0.txt"
cp "$ROOT/LICENSES/Notes-Engine-MIT.txt" "$APP/Contents/Resources/Licenses/Notes-Engine-MIT.txt"
cp "$ROOT/install-sensor-helper.sh" "$APP/Contents/Resources/install-sensor-helper.sh"
cp "$ROOT/uninstall-sensor-helper.sh" "$APP/Contents/Resources/uninstall-sensor-helper.sh"
cp "$ROOT/TorliStatsHelper.plist" "$APP/Contents/Library/LaunchDaemons/TorliStatsHelper.plist"

# LaunchDaemon authorization requires a Developer ID signed/notarized app.
# Local development keeps using the ad-hoc '-' identity by default.
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP" >/dev/null

# Also install the freshly built app so the next build immediately updates
# the copy used by macOS. Override with SKIP_INSTALL=1 when needed.
if [[ "${SKIP_INSTALL:-0}" != "1" ]]; then
    INSTALL_APP="/Applications/TorliStats.app"

    # Stop the running copy before replacing it, then launch the new build.
    osascript -e 'tell application id "local.torli.stats" to quit' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$INSTALL_APP"
    ditto "$APP" "$INSTALL_APP"
    open "$INSTALL_APP"
    printf 'Installed and restarted %s\n' "$INSTALL_APP"
fi

printf 'Built %s\n' "$APP"
printf 'Run with: open "%s"\n' "$APP"
