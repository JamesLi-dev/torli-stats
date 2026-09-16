import SwiftUI

enum DashboardPalette {
    static let cpuBars = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.84, blue: 0.50),
            Color(red: 0.15, green: 0.68, blue: 0.36)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let inputBars = LinearGradient(
        colors: [
            Color(red: 0.34, green: 0.68, blue: 0.98),
            Color(red: 0.20, green: 0.48, blue: 0.90)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let diskProgress = Color(red: 0.25, green: 0.56, blue: 0.94)
    static let activity = Color(red: 0.72, green: 0.38, blue: 0.88)
    static let quotaSuccess = Color(red: 0.17, green: 0.72, blue: 0.40)
    static let quotaWarning = Color(red: 0.92, green: 0.57, blue: 0.16)
    static let quotaCritical = Color(red: 0.88, green: 0.25, blue: 0.28)
}

struct DashboardChip: View {
    let text: String
    var tint: Color = Color.primary.opacity(0.78)
    var fontSize: CGFloat = 9
    var weight: Font.Weight = .medium
    var verticalPadding: CGFloat = 3
    var cornerRadius: CGFloat = 6

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.15), lineWidth: 0.6)
            }
    }
}

struct DashboardIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DashboardIconButtonLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct DashboardIconButtonLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @State private var isHovered = false

    private var surfaceColor: Color {
        if isPressed { return Color.primary.opacity(0.13) }
        if isHovered { return Color.primary.opacity(0.08) }
        return .clear
    }

    var body: some View {
        label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(width: 22, height: 22)
            .background(surfaceColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(isHovered ? 0.12 : 0), lineWidth: 0.6)
            }
            .scaleEffect(isPressed ? 0.90 : (isHovered ? 1.04 : 1))
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.10), value: isPressed)
            .onHover { isHovered = $0 }
    }
}

struct DashboardProgressBar: View {
    let value: Double
    let tint: Color
    let height: CGFloat

    init(value: Double, tint: Color, height: CGFloat = DashboardLayout.progressBarHeight) {
        self.value = value
        self.tint = tint
        self.height = height
    }

    private var clampedValue: Double {
        min(1, max(0, value))
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.76), tint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fillGradient)
                        .frame(width: proxy.size.width * clampedValue)
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                        .animation(.easeOut(duration: 0.32), value: clampedValue)
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
