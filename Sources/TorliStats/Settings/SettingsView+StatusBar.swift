import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var statusBarSection: some View {
        SettingsSection(title: "状态栏") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSubsectionTitle("菜单栏显示内容")
                    LazyVGrid(columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ], alignment: .leading, spacing: 10) {
                        Toggle("CPU", isOn: $settings.showCPU)
                        Toggle("内存", isOn: $settings.showMemory)
                        Toggle("下载", isOn: $settings.showDownload)
                        Toggle("上传", isOn: $settings.showUpload)
                    }
                    HStack(spacing: 12) {
                        Toggle("Codex 进度", isOn: $settings.showCodexStatusItem)
                            .frame(width: 110, alignment: .leading)
                        Toggle("输入统计", isOn: $settings.showTypingStatusItem)
                            .frame(width: 90, alignment: .leading)
                        Picker("", selection: $settings.codexStatusMetric) {
                            ForEach(CodexStatusMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 90)
                    }
                    HStack(spacing: 12) {
                        SettingsFieldLabel("Codex 展示")
                        Picker("", selection: $settings.codexStatusBarMode) {
                            ForEach(CodexStatusBarMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }

                    Divider()

                    SettingsSubsectionTitle("系统指标样式")
                    HStack(spacing: 12) {
                        SettingsFieldLabel("显示方式")
                        Picker("", selection: $settings.systemStatusBarStyle) {
                            ForEach(SystemStatusBarStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 132)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Toggle("显示 Logo", isOn: $settings.showStatusBarLogo)
                                .fixedSize(horizontal: true, vertical: false)
                            Toggle("随 CPU 加速", isOn: $settings.statusBarLogoAnimation)
                                .toggleStyle(.switch)
                                .fixedSize(horizontal: true, vertical: false)
                                .disabled(!settings.showStatusBarLogo)
                        }
                        HStack(spacing: 12) {
                            SettingsFieldLabel("动画样式")
                            Picker("", selection: $settings.statusBarRunner) {
                                ForEach(StatusBarRunner.allCases) { runner in
                                    Text(runner.title).tag(runner)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 130)
                            .disabled(!settings.showStatusBarLogo)
                        }
                    }
                Text("关闭“随 CPU 加速”后以固定 8 FPS 播放；系统启用“减少动态效果”时自动显示静态图标。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var statusBarOrderSection: some View {
        SettingsSection(title: "菜单栏项目顺序") {
            VStack(alignment: .leading, spacing: 7) {
                    Text("仅显示已启用的项目；拖动调整其状态栏顺序。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 185), alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(visibleStatusBarGroups) { group in
                            HStack(spacing: 8) {
                                Image(systemName: group == .logo ? "figure.run" : "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                Text(group.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.and.down")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onDrag {
                                draggedStatusBarGroup = group
                                return NSItemProvider(object: group.rawValue as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: StatusBarMetricGroupDropDelegate(
                                    target: group,
                                    groups: $settings.statusBarMetricOrder,
                                    draggedGroup: $draggedStatusBarGroup
                                )
                            )
                        }
                    }

                    Button("恢复默认顺序") {
                        settings.resetStatusBarMetricOrder()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
    }
}
