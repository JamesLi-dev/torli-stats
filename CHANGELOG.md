# Changelog

All notable changes to Torli Stats are documented here.

## [1.5.4] - 2026-09-17

<!-- ai-changelog:manual-1.5.4 -->
### English
- Adds a bilingual user and developer guide covering Input Monitoring, WakaTime Keychain access, the sensor helper, stable code signing, and upgrade troubleshooting.
- Refines Dashboard visual surfaces:
  - Unifies Codex account cards, WakaTime summaries, power details, empty states, and loading states with neutral glass surfaces and clearer outlines.
  - Improves Dashboard module spacing, Heatmap cell definition, Chip depth, and light-mode card hierarchy without changing data behavior.
- Prevents launch-time CPU spikes from being reported as a misleading `100%` value by ignoring back-to-back startup samples and warming up the CPU sampler after a baseline reset.
- Validation: `swift test`, `swift build`, `./build-app.sh`, `git diff --check`, and `plutil -lint Info.plist` passed.

### 中文
- 新增中英文用户与开发者说明书，覆盖输入监控、WakaTime 钥匙串访问、传感器辅助进程、稳定代码签名和升级排查。
- 改进 Dashboard 的显示质感：
  - 统一 Codex 账户卡片、WakaTime 摘要、电源详情、空状态和加载状态的中性玻璃表面与轮廓。
  - 改善 Dashboard 模块间距、Heatmap 格子边界、Chip 层次和亮色模式卡片层次，不改变数据行为。
- 通过忽略启动阶段连续产生的 CPU 采样，并在基线重置后重新进行 CPU 采样预热，避免将启动瞬间的负载误显示为 `100%`。
- 验证通过：`swift test`、`swift build`、`./build-app.sh`、`git diff --check` 和 `plutil -lint Info.plist`。
