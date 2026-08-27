#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/TorliStats.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
  "$APP/Contents/Library/LaunchDaemons" \
  "$APP/Contents/Library/LaunchServices"
cp "$BIN_DIR/TorliStats" "$APP/Contents/MacOS/TorliStats"
cp "$BIN_DIR/TorliStatsHelper" \
  "$APP/Contents/Library/LaunchServices/TorliStatsHelper"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
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
