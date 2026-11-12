import SwiftUI

struct TemperatureTag: View {
    let value: Double?

    private var color: Color {
        AppColors.temperature(value)
    }

    var body: some View {
        Text(value.map { StatsL10n.format("dashboard.temperature", $0) } ?? StatsL10n.text("dashboard.temperature_unavailable"))
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(value == nil ? 0.08 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(StatsL10n.text("dashboard.temperature_accessibility"))
            .accessibilityValue(value.map { StatsL10n.format("dashboard.temperature_celsius", $0) } ?? StatsL10n.text("dashboard.unavailable"))
    }
}
