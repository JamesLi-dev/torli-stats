import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var dashboardSection: some View {
        SettingsSection(title: StatsL10n.text("settings.dashboard_modules")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(StatsL10n.text("dashboard.density"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.dashboardDensity) {
                        ForEach(DashboardDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 18) {
                    Toggle(StatsL10n.text("settings.dashboard.show_device_info"), isOn: $settings.showDashboardDeviceInfo)
                    Toggle(StatsL10n.text("settings.dashboard.show_temperature_tags"), isOn: $settings.showTemperatureTags)
                    Toggle(StatsL10n.text("settings.dashboard.show_process_pid"), isOn: $settings.showProcessPID)
                }
                .font(.caption)

                Divider()

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], alignment: .leading, spacing: 10) {
                    Toggle("CPU", isOn: $settings.showCPUCard)
                    Toggle("GPU", isOn: $settings.showGPUCard)
                    Toggle(StatsL10n.text("module.memory"), isOn: $settings.showMemoryCard)
                    Toggle(StatsL10n.text("module.disk"), isOn: $settings.showDiskCard)
                    Toggle(StatsL10n.text("module.network"), isOn: $settings.showNetworkCard)
                    Toggle(StatsL10n.text("module.fan"), isOn: $settings.showFanCard)
                    Toggle(StatsL10n.text("module.typing"), isOn: $settings.showTypingCard)
                    Toggle(StatsL10n.text("module.power"), isOn: $settings.showPowerCard)
                    Toggle(StatsL10n.text("module.processes"), isOn: $settings.showProcessesCard)
                    Toggle("Codex", isOn: $settings.showCodexCard)
                    Toggle("WakaTime", isOn: $settings.showWakaTimeCard)
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                Text(StatsL10n.text("dashboard.order_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(visibleDashboardModules) { module in
                        HStack(spacing: 7) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(module.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.and.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onDrag {
                            draggedDashboardModule = module
                            return NSItemProvider(object: module.rawValue as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: DashboardModuleDropDelegate(
                                target: module,
                                modules: $settings.dashboardModuleOrder,
                                draggedModule: $draggedDashboardModule
                            )
                        )
                    }
                }

                Button(StatsL10n.text("common.restore_default_order")) {
                    settings.resetDashboardModuleOrder()
                }
                .buttonStyle(.link)
                .font(.caption)
                }
            }
        }
    }
}
