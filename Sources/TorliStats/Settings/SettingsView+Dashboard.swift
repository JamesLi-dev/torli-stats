import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var dashboardSection: some View {
        SettingsSection(title: "面板模块") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("显示密度")
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

                Divider()

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], alignment: .leading, spacing: 10) {
                    Toggle("CPU", isOn: $settings.showCPUCard)
                    Toggle("GPU", isOn: $settings.showGPUCard)
                    Toggle("内存", isOn: $settings.showMemoryCard)
                    Toggle("磁盘", isOn: $settings.showDiskCard)
                    Toggle("网络", isOn: $settings.showNetworkCard)
                    Toggle("风扇", isOn: $settings.showFanCard)
                    Toggle("输入", isOn: $settings.showTypingCard)
                    Toggle("电源", isOn: $settings.showPowerCard)
                    Toggle("进程", isOn: $settings.showProcessesCard)
                    Toggle("Codex", isOn: $settings.showCodexCard)
                    Toggle("WakaTime", isOn: $settings.showWakaTimeCard)
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                Text("仅显示已启用的模块；拖动调整 Dashboard 顺序。")
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

                Button("恢复默认顺序") {
                    settings.resetDashboardModuleOrder()
                }
                .buttonStyle(.link)
                .font(.caption)
                }
            }
        }
    }
}
