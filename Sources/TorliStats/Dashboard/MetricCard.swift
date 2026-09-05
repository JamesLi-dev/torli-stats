import SwiftUI

struct MetricCard<Content: View, Footer: View>: View {
    let title: String
    let icon: String
    let value: String
    let badge: String
    let density: DashboardDensity
    let valueColor: Color
    let content: Content
    let footer: Footer

    init(title: String, icon: String, value: String, badge: String, density: DashboardDensity = .standard, valueColor: Color = .primary, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.icon = icon
        self.value = value
        self.badge = badge
        self.density = density
        self.valueColor = valueColor
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

    private var minimumHeight: CGFloat {
        switch density {
        case .compact: return 58
        case .standard: return 100
        case .detailed: return 114
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 3 : 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(badge)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(AppColors.badge)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)

            if density != .compact {
                content
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .frame(height: chartHeight)

                footer
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(density == .compact ? 6 : 6)
        .frame(minHeight: minimumHeight, alignment: .top)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
