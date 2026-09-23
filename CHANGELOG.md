# Changelog

All notable changes to Torli Stats are documented here.

## [Unreleased]

<!-- ai-changelog:e6424ed6cc4d -->
### 2026-09-23

### English

Torli Stats 1.6.1 adds an optional threshold color setting for menu bar usage values and changes how the animated runner and metrics are laid out.

- **Menu bar colors:** “Use Threshold Colors” applies green below 50%, orange from 50% through 80%, and red above 80% to CPU, memory, and Codex usage values. Stale Codex values use orange. The setting is off by default, persists in `UserDefaults`, updates the menu bar when changed, and returns to off with `resetToDefaults()`. Without it, the title has no explicit foreground color.
- **Runner and text layout:** The status button now uses its native `image` and `attributedTitle` instead of `StatusBarLayeredContentView`, which was removed. The runner is placed at the leading or trailing edge according to its position in `statusBarMetricOrder`; animation frames refresh the title. Sprite frames are cropped to their shared visible horizontal bounds to reduce transparent space beside the title.
- **Text alignment:** Metric groups now use measured attributed-string widths and invisible spacers to align their two lines, including localized labels.
- **Release metadata:** `VERSION` and `CFBundleShortVersionString` advance from `1.6.0` to `1.6.1`.

### 中文

Torli Stats 1.6.1 新增可选的菜单栏用量阶梯颜色，并调整了动态形象与指标文字的排版方式。

- **菜单栏颜色：**“使用阶梯颜色”开启后，CPU、内存和 Codex 用量低于 50% 时显示绿色，50% 至 80% 显示橙色，高于 80% 显示红色；过期的 Codex 数据显示橙色。该设置默认关闭，保存在 `UserDefaults` 中，切换后会更新菜单栏，执行 `resetToDefaults()` 时恢复为关闭。关闭时，标题文字不指定前景色。
- **动态形象与文字排版：**状态栏按钮改用原生 `image` 和 `attributedTitle`，并移除了 `StatusBarLayeredContentView`。动态形象根据其在 `statusBarMetricOrder` 中的位置放在文字前方或后方；动画帧更新时会刷新标题。精灵图帧会裁去各帧共同的水平透明边缘，缩小与文字之间的空白。
- **文字对齐：**指标分组改用富文本的实际测量宽度和不可见间隔对齐上下两行，包括本地化标签。
- **版本信息：**`VERSION` 和 `CFBundleShortVersionString` 从 `1.6.0` 更新为 `1.6.1`。
