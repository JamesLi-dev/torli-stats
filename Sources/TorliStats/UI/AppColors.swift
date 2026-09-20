import AppKit
import SwiftUI

/// Shared geometric values keep custom SwiftUI surfaces aligned across the app.
enum AppMetrics {
    static let microCornerRadius: CGFloat = 4
    static let compactCornerRadius: CGFloat = 6
    static let selectionCornerRadius: CGFloat = 9
    static let dashboardCardCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 14
    static let panelCornerRadius: CGFloat = 16

    static let compactPadding: CGFloat = 6
    static let contentPadding: CGFloat = 8
    static let sectionPadding: CGFloat = 14
    static let windowContentPadding: CGFloat = 28
    static let compactRowSpacing: CGFloat = 4
    static let sectionSpacing: CGFloat = 10
    static let iconButtonSize: CGFloat = 22
}

/// Reused type treatments for dense monitoring and settings surfaces.
enum AppTypography {
    static let navigation = Font.system(size: 14, weight: .regular)
    static let navigationSelected = Font.system(size: 14, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 12, weight: .medium, design: .rounded)
    static let detailTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let metricValue = Font.system(size: 19, weight: .bold, design: .rounded)
    static let detailMetric = Font.system(size: 17, weight: .bold, design: .rounded)
    static let metadata = Font.system(size: 10, weight: .medium, design: .rounded)
    static let compactMetadata = Font.system(size: 9, weight: .medium, design: .monospaced)
}

enum AppColors {
    // Neutral, system-like surfaces avoid a separate warm palette in each
    // window. The small luminance steps retain hierarchy without making the
    // sidebar and content area look like unrelated panels.
    static let backgroundNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.115, alpha: 1)
            : NSColor(calibratedRed: 0.955, green: 0.955, blue: 0.965, alpha: 1)
    }
    static let background = Color(nsColor: backgroundNSColor)
    // A translucent neutral veil keeps the wallpaper-backed glass bright and
    // avoids warm/grey wallpaper colours tinting Settings surfaces.
    static let settingsGlassTint = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.30),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.055)
    )
    static let card = adaptive(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.78),
        dark: NSColor(calibratedRed: 0.155, green: 0.155, blue: 0.170, alpha: 0.82)
    )
    static let badge = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.075),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )

    // Semantic status tokens use slightly brighter dark-mode variants so
    // status remains legible on the dashboard's dark card surfaces.
    static let accent = adaptive(
        light: NSColor(calibratedRed: 0.25, green: 0.56, blue: 0.94, alpha: 1),
        dark: NSColor(calibratedRed: 0.38, green: 0.66, blue: 1.0, alpha: 1)
    )
    static let activity = adaptive(
        light: NSColor(calibratedRed: 0.72, green: 0.38, blue: 0.88, alpha: 1),
        dark: NSColor(calibratedRed: 0.78, green: 0.50, blue: 0.96, alpha: 1)
    )
    static let success = adaptive(
        light: NSColor(calibratedRed: 0.17, green: 0.72, blue: 0.40, alpha: 1),
        dark: NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.51, alpha: 1)
    )
    static let caution = adaptive(
        light: NSColor(calibratedRed: 0.86, green: 0.65, blue: 0.16, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.74, blue: 0.28, alpha: 1)
    )
    static let warning = adaptive(
        light: NSColor(calibratedRed: 0.92, green: 0.57, blue: 0.16, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.25, alpha: 1)
    )
    static let critical = adaptive(
        light: NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.28, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.43, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Applies the same hover, pressed, and selected feedback to custom controls
/// without imposing a particular label layout or foreground colour.
struct AppSelectionButtonStyle: ButtonStyle {
    let isSelected: Bool
    var tint: Color = .primary
    var cornerRadius: CGFloat = AppMetrics.selectionCornerRadius
    var horizontalPadding: CGFloat = 0
    var verticalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        AppSelectionButtonLabel(
            label: configuration.label,
            isSelected: isSelected,
            tint: tint,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            isPressed: configuration.isPressed
        )
    }
}

private struct AppSelectionButtonLabel<Label: View>: View {
    let label: Label
    let isSelected: Bool
    let tint: Color
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let isPressed: Bool
    @State private var isHovered = false

    private var surfaceColor: Color {
        if isPressed { return tint.opacity(isSelected ? 0.22 : 0.14) }
        if isSelected { return tint.opacity(isHovered ? 0.16 : 0.11) }
        if isHovered { return Color.primary.opacity(0.07) }
        return .clear
    }

    private var borderColor: Color {
        if isSelected { return tint.opacity(0.24) }
        if isHovered { return Color.primary.opacity(0.14) }
        return .clear
    }

    var body: some View {
        label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(surfaceColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.10), value: isPressed)
            .onHover { isHovered = $0 }
    }
}
