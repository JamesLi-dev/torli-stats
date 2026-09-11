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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }
}

struct DetailMetricGrid: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
    }
}
