import SwiftUI

struct MetricCard<Content: View, Footer: View>: View {
    let title: String
    let icon: String
    let value: String
    let badge: String
    let density: DashboardDensity
    let valueColor: Color
    let badgeColor: Color
    let isInteractive: Bool
    let content: Content
    let footer: Footer

    init(title: String, icon: String, value: String, badge: String, density: DashboardDensity = .standard, valueColor: Color = .primary, badgeColor: Color = Color.primary.opacity(0.78), isInteractive: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.value = value
        self.badge = badge
        self.density = density
        self.valueColor = valueColor
        self.badgeColor = badgeColor
        self.isInteractive = isInteractive
        self.content = content()
        self.footer = footer()
    }

    private var chartHeight: CGFloat {
        switch density {
        case .compact: return 0
        case .standard: return 24
        case .detailed: return 38
        }
    }

    private var cardHeight: CGFloat {
        DashboardLayout.metricCardHeight(for: density)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 3 : 6) {
            HStack(alignment: .center) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Spacer()
                DashboardChip(
                    text: badge,
                    tint: badgeColor,
                    verticalPadding: 4
                )
            }

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())

            if density != .compact {
                content
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .frame(height: chartHeight)

                Spacer(minLength: 0)

                footer
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(density == .compact ? 6 : 6)
        .frame(height: cardHeight, alignment: .top)
        .dashboardCardSurface(interactive: isInteractive)
    }
}
