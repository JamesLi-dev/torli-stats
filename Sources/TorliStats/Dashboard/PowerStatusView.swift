import AppKit
import SwiftUI

struct PowerStatusView: View {
    let battery: BatterySnapshot
    let bluetoothBatteries: [BluetoothBatterySnapshot]
    let isPrivacyMode: Bool
    let density: DashboardDensity

    private let columns = [
        GridItem(.adaptive(minimum: 155), spacing: 10, alignment: .leading)
    ]

    private var batteryColor: Color { batteryLevelColor(battery.percentage) }

    private var healthColor: Color { batteryHealthColor(battery.health) }

    private var thermalColor: Color { thermalStateColor(battery.thermalState) }

    private var thermalText: String {
        switch battery.thermalState {
        case .nominal: return StatsL10n.text("dashboard.thermal.nominal")
        case .fair: return StatsL10n.text("dashboard.thermal.fair")
        case .serious: return StatsL10n.text("dashboard.thermal.serious")
        case .critical: return StatsL10n.text("dashboard.thermal.critical")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(StatsL10n.text("dashboard.power"), systemImage: battery.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if density != .compact {
                    HStack(spacing: 5) {
                        PowerTag(text: battery.health.map { StatsL10n.format("dashboard.health", Int($0)) } ?? StatsL10n.text("dashboard.health_unavailable"), color: healthColor)
                        PowerTag(text: thermalText, color: thermalColor)
                        PowerTag(text: battery.cycleCount.map { StatsL10n.format("dashboard.cycles", $0) } ?? StatsL10n.text("dashboard.cycles_unavailable"))
                    }
                }
            }

            if density == .compact {
                HStack(spacing: 8) {
                    CompactBluetoothBatteryRing(
                        value: battery.percentage,
                        icon: "laptopcomputer",
                        color: batteryColor,
                        accessibilityName: "MacBook"
                    )
                    ForEach(Array(bluetoothBatteries.prefix(4).enumerated()), id: \.offset) { index, device in
                        CompactBluetoothBatteryRing(
                            value: device.percentage,
                            icon: device.kind.icon,
                            color: batteryLevelColor(device.percentage),
                            accessibilityName: isPrivacyMode ? StatsL10n.format("dashboard.bluetooth_device", index + 1) : device.name
                        )
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Standard and detailed layouts keep every device in the same
                // two-column row style. Mixing full rows with compact rings made
                // grids with three or more accessories visually misalign.
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    BatteryRing(
                        value: battery.percentage,
                        title: "MacBook",
                        detail: battery.adapterWatts.map { StatsL10n.format("dashboard.power_source.watts", battery.powerSource, $0) } ?? battery.powerSource,
                        icon: "laptopcomputer",
                        color: batteryColor
                    )

                    ForEach(Array(bluetoothBatteries.enumerated()), id: \.offset) { index, device in
                        BatteryRing(
                            value: device.percentage,
                            title: isPrivacyMode ? StatsL10n.format("dashboard.bluetooth_device", index + 1) : device.name,
                            detail: device.detail,
                            icon: device.kind.icon,
                            color: batteryLevelColor(device.percentage)
                        )
                    }
                }
            }
        }
        .padding(8)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

struct PowerTag: View {
    let text: String
    var color: Color = Color.primary.opacity(0.78)

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(AppColors.badge)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
private func batteryLevelColor(_ percentage: Double?) -> Color {
    guard let percentage else { return .secondary }
    switch percentage {
    case ...10: return .red
    case ...20: return .orange
    case ...50: return .yellow
    default: return .green
    }
}

private func batteryHealthColor(_ health: Double?) -> Color {
    guard let health else { return .secondary }
    switch health {
    case ...70: return .red
    case ...80: return .orange
    case ...90: return .yellow
    default: return .green
    }
}

private func thermalStateColor(_ state: SystemThermalState) -> Color {
    switch state {
    case .nominal: return .green
    case .fair: return .yellow
    case .serious: return .orange
    case .critical: return .red
    }
}

private struct CompactBluetoothBatteryRing: View {
    let value: Double?
    let icon: String
    let color: Color
    let accessibilityName: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                .stroke(
                    value == nil ? Color.primary.opacity(0.18) : color,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .frame(width: 48, height: 48)
        .frame(maxWidth: .infinity, alignment: .center)
        .help(accessibilityName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(value.map { "\(Int($0))%" } ?? StatsL10n.text("dashboard.battery_unavailable"))
    }
}

struct BatteryRing: View {
    let value: Double?
    let title: String
    let detail: String
    let icon: String
    var color: Color = .green

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                    .stroke(value == nil ? Color.primary.opacity(0.18) : color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(value == nil ? .secondary : .primary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                        .help(title)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
