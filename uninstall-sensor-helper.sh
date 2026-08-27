#!/bin/bash
set -euo pipefail

INSTALL_HELPER="/Library/PrivilegedHelperTools/TorliStatsHelper"
PLIST="/Library/LaunchDaemons/local.torli.stats.helper.plist"

launchctl bootout system/local.torli.stats.helper 2>/dev/null || true
# launchd removes jobs asynchronously; wait before deleting the executable.
for _ in {1..20}; do
  if ! launchctl print system/local.torli.stats.helper >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

rm -f "$PLIST" "$INSTALL_HELPER"
echo "传感器辅助进程已卸载。"
