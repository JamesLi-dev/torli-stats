import AppKit
import SwiftUI

struct DeviceInfoView: View {
    let info: DeviceInfo
    let isPrivacyMode: Bool
    let density: DashboardDensity

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DashboardPalette.diskProgress.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DashboardPalette.diskProgress.opacity(0.22), lineWidth: 0.8)
                    }
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DashboardPalette.diskProgress)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isPrivacyMode ? StatsL10n.text("dashboard.this_mac") : info.model)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(info.system)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.badge)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                if density != .compact {
                    HStack(spacing: 6) {
                        InfoTag(text: "CPU  \(displayCPUModel)")
                        InfoTag(text: StatsL10n.format("dashboard.memory_tag", info.memory))
                    }
                }
            }

            Spacer(minLength: 6)

            if density != .compact {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(StatsL10n.text("dashboard.uptime"))
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    Text(info.uptime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardSurface()
    }

    private var displayCPUModel: String {
        info.cpuModel.hasPrefix("Apple ") ? String(info.cpuModel.dropFirst(6)) : info.cpuModel
    }
}

private struct InfoTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(DashboardPalette.diskProgress)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(DashboardPalette.diskProgress.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(DashboardPalette.diskProgress.opacity(0.14), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}
