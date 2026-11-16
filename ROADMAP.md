# Community roadmap / 社区版计划

This roadmap covers the open-source Community edition. Items are proposals, not release commitments or a fixed schedule. Completed implementation does not imply validation on every Mac. Detailed working checklists: [product](TODO.md) · [Notes](note-todo.md). These files are also public in this repository.

本计划面向开源社区版。待办是方向而非发布日期或交付承诺；代码完成不代表已在所有 Mac 上验证。详细工作清单：[产品](TODO.md) · [便签](note-todo.md)；这两份文件在本仓库中同样公开。

## Reliability and distribution / 稳定性与分发

- [ ] Validate monitoring and sleep/wake behavior on different Macs, including fanless models. / 在不同 Mac（包括无风扇机型）上验证监控与睡眠唤醒。
- [ ] Later, after obtaining Developer ID, prepare signing, notarization and stapling; verify permissions, Keychain and the sensor helper across upgrades. / 最后在申请获得 Developer ID 后准备签名、公证和装订，并验证升级后的权限、钥匙串与传感器助手。
- [ ] Improve release verification and publish SHA256 checksums. / 完善发布产物验证并提供 SHA256 校验值。
- [ ] Validate Community Homebrew Cask installation and upgrades; assess a separate Pro Cask and Intel or Universal builds. / 验证社区版 Homebrew Cask 的安装与升级，评估独立 Pro Cask 和 Intel 或通用架构构建。

## Dashboard and integrations / 面板与集成

- [ ] Evaluate dashboard information hierarchy and usability with all modules enabled, multiple accounts, small screens, themes and keyboard navigation. / 评估全部模块、多账号、小屏、主题和键盘操作下的面板信息层级与易用性。
- [ ] Explore selectable dashboard chart time ranges. / 探索可选择的面板图表时间范围。
- [ ] Evaluate a dedicated Codex Home import flow and improve visibility of per-account refresh, failure and cached-data times. / 评估独立的 Codex Home 导入流程，改善各账号刷新、失败和缓存时间的展示。
- [ ] Evaluate sensor-helper cleanup on app exit or uninstall. / 评估退出应用或卸载时的传感器助手清理策略。

## Notes / 便签

- [ ] Improve block-level Markdown, including nested lists and quotes, fenced code blocks and heading layout. / 完善块级 Markdown，包括嵌套列表与引用、代码围栏和标题布局。
- [ ] Improve discoverability and consistency of formatting controls, shortcuts and undo across Notes surfaces. / 改善各便签界面格式操作、快捷键和撤销的可发现性与一致性。
- [ ] Manually validate input methods, undo, images, backups, large documents and recovery after storage failures. / 人工验证输入法、撤销、图片、备份、大文本及存储失败后的恢复。

## Ideas to evaluate / 待评估方向

- [ ] Explore an alert center, work-mode presets and threshold presets. / 探索告警中心、工作模式和阈值预设。
- [ ] Explore shareable, privacy-conscious status snapshots and a sensor compatibility report. / 探索兼顾隐私的状态快照和传感器兼容性报告。
- [ ] Explore aggregate-statistics import/export without credentials or input content; Community settings now have a separate encrypted backup. / 探索不包含凭据或输入内容的聚合统计导入导出；社区版设置已提供独立加密备份。

Tables, additional attachment formats, Mermaid, mathematical notation and a full WYSIWYG Notes editor are not currently scheduled. / 表格、其他附件格式、Mermaid、数学公式和完整所见即所得便签编辑器目前不排期。
