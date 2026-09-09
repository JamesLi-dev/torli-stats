# Torli Stats

[中文说明](README_CN.md)

A lightweight, local system monitor for the macOS menu bar. Torli Stats keeps the most useful system metrics one click away without sending data to a server.

## Features

- CPU usage and per-core activity
- GPU usage when available through IOKit/IORegistry
- Memory usage
- Disk usage and free space
- Real-time network upload and download speeds
- Battery and charging status
- Fan speed and temperature sensors when authorized
- Top processes by CPU or memory usage
- Configurable menu bar items and dashboard modules
- Light, dark, and system appearance modes
- Night monitoring pause, enabled by default from 23:30 to 07:00
- Optional adaptive low-impact sampling after 25 minutes of idle time
- Typing and developer activity statistics with daily detail charts
- Integrated Torli Notes, including searchable all-notes and archive views
- Automatic and manual GitHub Release update checks
- Configurable refresh interval, process count, and sorting
- Launch at login

## Requirements

- macOS 15 or later
- Xcode Command Line Tools

## Run from source

```bash
swift run
```

## Build and install the app

```bash
./build-app.sh
```

The script builds a release version, signs it with the configured code-signing identity, installs it to `/Applications/TorliStats.app`, and restarts the running app automatically.

To build without installing or restarting the app:

```bash
SKIP_INSTALL=1 ./build-app.sh
```

## Usage

Click the CPU/MEM values in the menu bar to open the dashboard. Click outside the dashboard to close it. Right-click the menu bar item to refresh all data, switch privacy mode, open Settings, view app information, or quit Torli Stats.

The Settings window provides controls for appearance, menu bar metrics, refresh frequency, night monitoring pause, adaptive low-impact sampling, process display, dashboard modules, typing and developer statistics, sensor authorization, update checks, and launch at login. Settings are saved automatically.

Metrics, typing statistics, and Notes stay on this Mac. WakaTime API keys are stored in the macOS Keychain.

## Sensor helper

Fan speed and temperature readings may require the optional privileged sensor helper. Open Settings and choose **Authorize Fan and Temperature Access**. The app must be located in the Applications folder for the helper installation flow.

## Changelog workflow

`CHANGELOG.md` entries can be drafted locally from staged changes:

```bash
git add <files>
./scripts/generate-changelog.sh
# Review the generated entry, then stage it.
git add CHANGELOG.md
```

The script uses `codex` when available and otherwise `claude`; `AI_CHANGELOG_COMMAND` can provide another stdin-to-stdout command. Review every generated entry before committing. The script writes an `[Unreleased]` entry and backs up the previous changelog under the ignored `.changelog-backups/` directory. An optional hook is available with `./scripts/setup-git-hooks.sh` and `AI_CHANGELOG_ON_COMMIT=1`.

## Build and release automation

`VERSION` is the source of truth for the user-visible semantic version. Bump it with:

```bash
./scripts/bump-version.sh major  # 1.2.3 → 2.0.0
./scripts/bump-version.sh minor  # 1.2.3 → 1.3.0
./scripts/bump-version.sh patch  # 1.2.3 → 1.2.4
```

Commit the resulting `VERSION`, `Info.plist`, and reviewed changelog changes, then push them to `main`. The GitHub Actions workflow runs on `main`, builds an arm64 archive, and—when that version has not already been released—creates the matching `vX.Y.Z` tag and GitHub Release automatically. Do not rely on manually pushing a version tag to start the workflow.

## Notes

macOS does not provide a stable public GPU utilization API. Torli Stats reads the `Renderer Utilization %` and `Device Utilization %` fields from IORegistry when available and avoids interpreting memory values from the same row as GPU utilization.
