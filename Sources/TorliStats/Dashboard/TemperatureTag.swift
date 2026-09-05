import SwiftUI

struct TemperatureTag: View {
    let value: Double?

    private var color: Color {
        guard let value else { return .secondary }
        if value >= 90 { return .red }
        if value >= 80 { return Color(red: 0.82, green: 0.22, blue: 0.04) }
        if value >= 65 { return .orange }
        return .green
    }

    var body: some View {
        Text(value.map { String(format: "温度 %.0f°C", $0) } ?? "温度 —")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(value == nil ? 0.08 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("温度")
            .accessibilityValue(value.map { String(format: "%.0f 摄氏度", $0) } ?? "不可用")
    }
}
