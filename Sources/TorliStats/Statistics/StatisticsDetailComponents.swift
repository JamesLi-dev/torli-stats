import SwiftUI
import AppKit

struct DetailSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let headerAccessory: AnyView
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        headerAccessory: AnyView = AnyView(EmptyView()),
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerAccessory = headerAccessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppMetrics.sectionSpacing) {
            HStack(alignment: .center, spacing: AppMetrics.contentPadding) {
                Text(title)
                    .font(AppTypography.detailTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.metadata.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                headerAccessory
            }
            .frame(maxWidth: .infinity)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCardSurface()
    }
}

struct DetailMetricGrid: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(AppTypography.detailMetric)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct BreakdownList: View {
    let values: [WakaTimeBreakdown]
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ForEach(values) { value in
                HStack(spacing: 9) {
                    Text(value.name)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color.opacity(0.82))
                            .frame(width: max(2, proxy.size.width * min(1, value.percent / 100)))
                            .frame(maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 4)
                    Text(StatisticsFormatting.compactDuration(value.totalSeconds))
                        .font(AppTypography.metadata.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }
}
