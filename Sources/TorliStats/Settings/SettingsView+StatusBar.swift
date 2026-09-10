import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var statusBarSection: some View {
        SettingsSection(title: StatsL10n.text("settings.category.status_bar")) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSubsectionTitle(StatsL10n.text("settings.status_bar.displayed_content"))
                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 130), alignment: .leading),
                        GridItem(.flexible(minimum: 130), alignment: .leading),
                        GridItem(.flexible(minimum: 130), alignment: .leading),
                        GridItem(.flexible(minimum: 130), alignment: .leading)
                    ], alignment: .leading, spacing: 10) {
                        Toggle("CPU", isOn: $settings.showCPU)
                        Toggle(StatsL10n.text("module.memory"), isOn: $settings.showMemory)
                        Toggle(StatsL10n.text("settings.status_bar.download"), isOn: $settings.showDownload)
                        Toggle(StatsL10n.text("settings.status_bar.upload"), isOn: $settings.showUpload)
                        Toggle(StatsL10n.text("settings.status_bar.codex_progress"), isOn: $settings.showCodexStatusItem)
                            .fixedSize(horizontal: true, vertical: false)
                        Toggle(StatsL10n.text("settings.status_bar.typing"), isOn: $settings.showTypingStatusItem)
                            .fixedSize(horizontal: true, vertical: false)
                        Picker("", selection: $settings.codexStatusMetric) {
                            ForEach(CodexStatusMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                    HStack(spacing: 12) {
                        Text(StatsL10n.text("settings.status_bar.codex_display"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 118, alignment: .leading)
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

                    SettingsSubsectionTitle(StatsL10n.text("settings.status_bar.system_metrics_style"))
                    HStack(spacing: 12) {
                        SettingsFieldLabel(StatsL10n.text("settings.status_bar.display_style"))
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
                            Toggle(StatsL10n.text("settings.status_bar.show_logo"), isOn: $settings.showStatusBarLogo)
                                .fixedSize(horizontal: true, vertical: false)
                            Toggle(StatsL10n.text("settings.status_bar.animate_with_cpu"), isOn: $settings.statusBarLogoAnimation)
                                .toggleStyle(.switch)
                                .fixedSize(horizontal: true, vertical: false)
                                .disabled(!settings.showStatusBarLogo)
                        }
                        HStack(spacing: 12) {
                            Text(StatsL10n.text("settings.status_bar.animation_style"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 118, alignment: .leading)
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
                Text(StatsL10n.text("settings.status_bar.animation_hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var statusBarOrderSection: some View {
        SettingsSection(title: StatsL10n.text("settings.status_bar.item_order")) {
            VStack(alignment: .leading, spacing: 7) {
                    Text(StatsL10n.text("settings.status_bar.item_order_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), alignment: .leading)],
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

                    Button(StatsL10n.text("common.restore_default_order")) {
                        settings.resetStatusBarMetricOrder()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
    }
}
