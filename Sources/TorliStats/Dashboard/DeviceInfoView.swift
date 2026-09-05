import AppKit
import SwiftUI

struct DeviceInfoView: View {
    let info: DeviceInfo
    let isPrivacyMode: Bool
    let density: DashboardDensity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isPrivacyMode ? "此 Mac" : info.model)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(info.system)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.badge)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Spacer(minLength: 0)
                }
                if density != .compact {
                    HStack(spacing: 6) {
                        InfoTag(text: "CPU  \(displayCPUModel)")
                        InfoTag(text: "内存  \(info.memory)")
                    }
                }
            }

            Spacer()

            if density != .compact {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("运行时间")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(info.uptime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
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
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(AppColors.badge)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}
