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

    private var batteryColor: Color {
        let percentage = battery.percentage
        if percentage <= 10 { return .red }
        if percentage <= 20 { return .orange }
        return .green
    }

    private var healthColor: Color {
        guard let health = battery.health else { return .secondary }
        if health <= 70 { return .red }
        if health <= 80 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("电源", systemImage: battery.isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if density != .compact {
                    HStack(spacing: 5) {
                        PowerTag(text: battery.health.map { "健康 \(Int($0))%" } ?? "健康 —", color: healthColor)
                        PowerTag(text: battery.cycleCount.map { "循环 \($0) 次" } ?? "循环 —")
                    }
                }
            }

            if density == .compact {
                HStack(spacing: 8) {
                    CompactBluetoothBatteryRing(
                        value: battery.percentage,
                        icon: "laptopcomputer",
                        accessibilityName: "MacBook"
                    )
                    ForEach(Array(bluetoothBatteries.prefix(4).enumerated()), id: \.offset) { index, device in
                        CompactBluetoothBatteryRing(
                            value: device.percentage,
                            icon: device.kind.icon,
                            accessibilityName: isPrivacyMode ? "蓝牙设备 \(index + 1)" : device.name
                        )
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Keep every device in a flexible two-column grid. With more than
                // two Bluetooth devices, compact rings prevent a long device list.
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    BatteryRing(
                        value: battery.percentage,
                        title: "MacBook",
                        detail: battery.adapterWatts.map { "\(battery.powerSource)  \($0) W" } ?? battery.powerSource,
                        icon: "laptopcomputer",
                        color: batteryColor
                    )

                    ForEach(Array(bluetoothBatteries.enumerated()), id: \.offset) { index, device in
                        if bluetoothBatteries.count > 2 {
                            CompactBluetoothBatteryRing(
                                value: device.percentage,
                                icon: device.kind.icon,
                                accessibilityName: isPrivacyMode ? "蓝牙设备 \(index + 1)" : device.name
                            )
                        } else {
                            BatteryRing(
                                value: device.percentage,
                                title: isPrivacyMode ? "蓝牙设备 \(index + 1)" : device.name,
                                detail: device.detail,
                                icon: device.kind.icon
                            )
                        }
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
private struct CompactBluetoothBatteryRing: View {
    let value: Double?
    let icon: String
    let accessibilityName: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, value ?? 0)) / 100))
                .stroke(
                    value == nil ? Color.primary.opacity(0.18) : Color.green,
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
        .accessibilityValue(value.map { "\(Int($0))%" } ?? "电量不可用")
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
