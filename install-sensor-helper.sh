#!/bin/bash
set -euo pipefail

APP="${1:-/Applications/TorliStats.app}"
SOURCE_HELPER="$APP/Contents/Library/LaunchServices/TorliStatsHelper"
INSTALL_DIR="/Library/PrivilegedHelperTools"
INSTALL_HELPER="$INSTALL_DIR/TorliStatsHelper"
PLIST="/Library/LaunchDaemons/local.torli.stats.helper.plist"

if [[ ! -x "$SOURCE_HELPER" ]]; then
  echo "找不到辅助进程：$SOURCE_HELPER" >&2
  exit 1
fi

install -d -o root -g wheel -m 755 "$INSTALL_DIR"
install -o root -g wheel -m 755 "$SOURCE_HELPER" "$INSTALL_HELPER"

TMP_PLIST="$(mktemp /tmp/local.torli.stats.helper.XXXXXX.plist)"
trap 'rm -f "$TMP_PLIST"' EXIT
cat > "$TMP_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.torli.stats.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_HELPER</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>local.torli.stats.sensor</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

chown root:wheel "$TMP_PLIST"
chmod 644 "$TMP_PLIST"

launchctl bootout system/local.torli.stats.helper 2>/dev/null || true
# bootout is asynchronous; waiting avoids a race where bootstrap returns
# EIO/"Operation already in progress" while launchd is still removing the
# previous helper instance.
for _ in {1..20}; do
  if ! launchctl print system/local.torli.stats.helper >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
install -o root -g wheel -m 644 "$TMP_PLIST" "$PLIST"
launchctl bootstrap system "$PLIST"
launchctl enable system/local.torli.stats.helper 2>/dev/null || true

echo "传感器辅助进程已安装并启动。"
