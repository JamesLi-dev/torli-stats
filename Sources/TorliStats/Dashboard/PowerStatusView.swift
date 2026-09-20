import AppKit
import SwiftUI

struct PowerStatusView: View {
    let battery: BatterySnapshot
    let bluetoothBatteries: [BluetoothBatterySnapshot]
    let isPrivacyMode: Bool
    let density: DashboardDensity

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading)
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
                // Standard and detailed layouts always use two equal-width
                // device cells, so accessories stay balanced as a compact grid.
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
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
                .padding(.horizontal, 5)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.026), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.34),
                                    Color.black.opacity(0.07)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.7
                        )
                }
            }
        }
        .padding(8)
        .dashboardCardSurface()
    }
}

struct PowerTag: View {
    let text: String
    var color: Color = Color.primary.opacity(0.78)

    var body: some View {
        DashboardChip(
            text: text,
            tint: color,
            verticalPadding: 4
        )
    }
}
private func batteryLevelColor(_ percentage: Double?) -> Color {
    guard let percentage else { return .secondary }
    switch percentage {
    case ...10: return DashboardPalette.quotaCritical
    case ...20: return DashboardPalette.quotaWarning
    case ...50: return AppColors.caution
    default: return DashboardPalette.quotaSuccess
    }
}

private func batteryHealthColor(_ health: Double?) -> Color {
    guard let health else { return .secondary }
    switch health {
    case ...70: return DashboardPalette.quotaCritical
    case ...80: return DashboardPalette.quotaWarning
    case ...90: return AppColors.caution
    default: return DashboardPalette.quotaSuccess
    }
}

private func thermalStateColor(_ state: SystemThermalState) -> Color {
    switch state {
    case .nominal: return DashboardPalette.quotaSuccess
    case .fair: return AppColors.caution
    case .serious: return DashboardPalette.quotaWarning
    case .critical: return DashboardPalette.quotaCritical
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
                    value == nil
                        ? AnyShapeStyle(Color.primary.opacity(0.18))
                        : AnyShapeStyle(AngularGradient(
                            colors: [color.opacity(0.58), color, color.opacity(0.82)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        )),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: value)
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
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                    .stroke(
                        value == nil
                            ? AnyShapeStyle(Color.primary.opacity(0.18))
                            : AnyShapeStyle(AngularGradient(
                                colors: [color.opacity(0.58), color, color.opacity(0.82)],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            )),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: value)
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(value == nil ? .secondary : .primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                        .help(title)
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}