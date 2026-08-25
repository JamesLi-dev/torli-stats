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
- Power-saving sampling mode
- Configurable refresh interval, process count, and sorting
- Launch at login

## Requirements

- macOS 13 or later
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

Click the CPU/MEM values in the menu bar to open the dashboard. Click outside the dashboard to close it. Right-click the menu bar item to open Settings or quit Torli Stats.

The Settings window provides controls for appearance, menu bar metrics, refresh frequency, power-saving mode, process display, dashboard modules, sensor authorization, and launch at login. Settings are saved automatically.

## Sensor helper

Fan speed and temperature readings may require the optional privileged sensor helper. Open Settings and choose **Authorize Fan and Temperature Access**. The app must be located in the Applications folder for the helper installation flow.

## AI-assisted changelog

`CHANGELOG.md` can be generated locally from the staged diff so that entries describe user-visible behavior and implementation details instead of only repeating commit subjects:

```bash
git add <files>
./scripts/generate-changelog.sh
# Review the generated entry, then stage it
git add CHANGELOG.md
git commit -m "..."
```

The script uses `codex` when available, then falls back to `claude`. To use another local AI command that reads the prompt from stdin and writes Markdown to stdout, set `AI_CHANGELOG_COMMAND`. The generated text must be reviewed before committing.

An optional pre-commit hook is available:

```bash
./scripts/setup-git-hooks.sh
AI_CHANGELOG_ON_COMMIT=1 git commit -m "..."
```

## Build and release automation

Every update to `main` builds an arm64 macOS app and uploads it as a GitHub Actions artifact. Pushing a version tag such as `v0.1.0` creates a GitHub Release with the archived app and the matching `CHANGELOG.md` section. Before tagging, move the reviewed `[Unreleased]` entry under a version heading.

## Changelog workflow

Detailed changelog entries can be generated locally from the staged diff with an installed `codex` or `claude` CLI:

```bash
./scripts/generate-changelog.sh
# Review the generated entry, then stage it:
git add CHANGELOG.md
```

The script only analyzes staged changes and does not claim behavior that is not supported by the diff. To enable the optional pre-commit hook:

```bash
./scripts/setup-git-hooks.sh
AI_CHANGELOG_ON_COMMIT=1 git commit
```

The GitHub Actions workflow builds an artifact for every `main` update. Pushing a version tag such as `v0.1.0` also creates a GitHub Release and uploads the app archive. For detailed tag notes, move the reviewed `[Unreleased]` section to a `[vX.Y.Z]` section before tagging.

## Notes

macOS does not provide a stable public GPU utilization API. Torli Stats reads the `Renderer Utilization %` and `Device Utilization %` fields from IORegistry when available and avoids interpreting memory values from the same row as GPU utilization.
