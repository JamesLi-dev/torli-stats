# Torli Stats

[中文说明](README_CN.md) · [User guide](docs/user-guide.md)

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
- Today’s typing count, active time, and WakaTime coding time (historical analysis is available in Pro)
- Torli Notes: edge deck, floating notes, search, archive, task lists, PNG/JPEG insertion, resizing, cropping, and image-inclusive backups
- Multiple Codex accounts, quota tracking, and local token activity
- Automatic and manual GitHub Release update checks
- Configurable refresh interval, process count, and sorting
- Launch at login

## Download

Download the Apple Silicon (arm64) archive from [Latest Release](https://github.com/JamesLi-dev/torli-stats/releases/latest), extract it, and move `TorliStats.app` to `/Applications`. Launch it, then click the menu-bar item to open the dashboard or right-click to open Settings.

Current releases use ad-hoc signing and are not Developer ID notarized. macOS may block first launch or request permissions again after an upgrade. The release workflow does not currently publish Intel or Universal packages.

## Requirements

- macOS 15 or later
- Xcode Command Line Tools (source builds only)

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

Monitoring data, typing aggregates, and Notes stay on this Mac. Enabled Codex, WakaTime, and update checks contact their respective services. WakaTime uses a personal OAuth token with `read_summaries` permission, stored in the macOS Keychain; legacy API keys must be replaced manually.

Note bodies are encrypted in the local database; this does not cover image files or exported backups. Use `.stickies` for image-inclusive backups, or keep Markdown exports together with their image folders. See the [user guide](docs/user-guide.md) for setup, shortcuts, and backup instructions.

Community includes Notes and Codex. Pro adds historical typing/WakaTime analysis and email verification-code features.

## Sensor helper

Fan speed and temperature readings may require the optional privileged sensor helper. Open Settings and choose **Authorize Fan and Temperature Access**. The app must be located in the Applications folder for the helper installation flow.

## Notes

macOS does not provide a stable public GPU utilization API. Torli Stats reads the `Renderer Utilization %` and `Device Utilization %` fields from IORegistry when available and avoids interpreting memory values from the same row as GPU utilization.

## Development and roadmap

This repository provides the standalone Community app and the `TorliStatsCore` Swift Package.

- [Architecture](ARCHITECTURE.md)
- [Development, signing, changelog, and release workflow](docs/development.md)
- [Product roadmap](TODO.md) · [Notes roadmap](note-todo.md)
- [Changelog](CHANGELOG.md)
