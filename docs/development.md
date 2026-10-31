# Development and distribution / 开发与分发

[使用指南 / User guide](user-guide.md) · [架构 / Architecture](../ARCHITECTURE.md)

当前 CI 发布 arm64 包，使用 ad-hoc 签名，尚未配置 Developer ID 公证与 stapling。以下 Developer ID 流程是正式分发的准备工作，不代表现有下载包已公证。

Current CI publishes an ad-hoc-signed arm64 archive. Developer ID notarization and stapling are not configured; the guidance below describes preparation for that distribution path.

## 验证 / Validation

```bash
swift test
python3 scripts/check-community-boundary.py
```

## 开发者发布指南

### 必须保持稳定的身份

发布和升级时请保持：

- `CFBundleIdentifier` 不变，目前是 `local.torli.stats`；
- 使用同一个 Apple Developer Team；
- 使用稳定的 Developer ID Application 证书；
- App 和内置的 `TorliStatsHelper` 使用一致、可验证的签名；
- 不要让用户在同一个路径混用 ad-hoc、本地调试和正式发布版本；
- 版本升级只改变版本号和构建内容，不随意更换 Bundle ID 或签名主体。

### 使用 Developer ID 构建

在已经安装 Developer ID Application 证书的机器上，可以将签名身份传给当前构建脚本：

```bash
security find-identity -v -p codesigning

CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./build-app.sh
```

当前脚本默认是 ad-hoc 签名：

```bash
./build-app.sh
# 等价于使用 CODE_SIGN_IDENTITY=-
```

这适合本地开发和 UI 调试，但不适合作为需要长期保留 TCC/Keychain 身份的正式更新渠道。

### 发布前检查

正式发布前至少应完成：

```bash
codesign --verify --deep --strict --verbose=2 TorliStats.app
spctl --assess --type execute --verbose=4 TorliStats.app
plutil -lint TorliStats.app/Contents/Info.plist
```

还应在干净用户账户或测试 Mac 上验证以下升级路径：

1. 安装旧的 Developer ID 版本。
2. 授予 Input Monitoring 权限并保存 WakaTime Token。
3. 安装新的 Developer ID 版本覆盖旧版本。
4. 确认输入统计仍能工作，且 WakaTime Token 不需要重新录入。
5. 单独测试传感器辅助进程的重新安装和版本升级。

当前仓库的 `build-app.sh` 负责构建、复制资源、签名和本地安装；正式的 Developer ID 证书管理、Hardened Runtime、notarization、stapling 和发布包上传仍属于发行环境配置的一部分，不能由用户授权替代。


## Changelog 工作流

可通过已安装的 `codex` 或 `claude` CLI，根据已暂存的变更在本地起草 Changelog：

```bash
git add <文件>
./scripts/generate-changelog.sh
# 检查生成内容后再暂存。
git add CHANGELOG.md
```

脚本只分析已暂存的变更；也可通过 `AI_CHANGELOG_COMMAND` 指定其他从标准输入读取、向标准输出写入内容的命令。提交前必须人工检查生成内容。脚本会写入一个 `[Unreleased]` 条目，并把旧 Changelog 备份到 `.gitignore` 排除的 `.changelog-backups/` 目录。可通过 `./scripts/setup-git-hooks.sh` 和 `AI_CHANGELOG_ON_COMMIT=1` 启用可选的提交前 Hook。

## 构建与发布自动化

`VERSION` 是用户可见的语义化版本来源，可使用以下命令升级：

```bash
./scripts/bump-version.sh major  # 1.2.3 → 2.0.0
./scripts/bump-version.sh minor  # 1.2.3 → 1.3.0
./scripts/bump-version.sh patch  # 1.2.3 → 1.2.4
```

提交生成的 `VERSION`、`Info.plist` 和已检查的 Changelog 后，将它们推送到 `main`。GitHub Actions 只在 `main` 上运行：它会构建 arm64 App 压缩包；若该版本尚未发布，则自动创建对应的 `vX.Y.Z` 标签和 GitHub Release。请不要依赖手动推送版本标签来触发工作流。


## Developer distribution guide

### Keep the identity stable

For release and upgrade continuity, keep the following unchanged:

- `CFBundleIdentifier`, currently `local.torli.stats`;
- the Apple Developer Team;
- the Developer ID Application certificate;
- a consistent, verifiable signature for both the app and the embedded `TorliStatsHelper`;
- the installation source at a given path; do not mix ad-hoc, debug, and release builds;
- the identity while changing only the version and build contents for an upgrade.

### Build with Developer ID

On a Mac with a Developer ID Application certificate installed, pass the signing identity to the current build script:

```bash
security find-identity -v -p codesigning

CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./build-app.sh
```

The current script defaults to ad-hoc signing:

```bash
./build-app.sh
# equivalent to CODE_SIGN_IDENTITY=-
```

That is suitable for local development and UI debugging, but not as a long-term update channel that must preserve TCC and Keychain identity.

### Pre-release checks

At minimum, verify the signed app before release:

```bash
codesign --verify --deep --strict --verbose=2 TorliStats.app
spctl --assess --type execute --verbose=4 TorliStats.app
plutil -lint TorliStats.app/Contents/Info.plist
```

Also test this upgrade path on a clean user account or test Mac:

1. Install the previous Developer ID build.
2. Grant Input Monitoring and save a WakaTime Token.
3. Install the new Developer ID build over the previous one.
4. Confirm that typing statistics still work and the WakaTime token does not need to be entered again.
5. Test sensor-helper reinstallation and upgrade separately.

The repository’s current `build-app.sh` builds the app, copies resources, signs it, and can install it locally. Developer ID certificate management, Hardened Runtime, notarization, stapling, and release-upload configuration remain part of the distribution environment; user authorization cannot replace them.


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

