import SwiftUI
import AppKit

struct DetailDailyValue: Identifiable {
    let dateID: String
    let value: Double
    let tooltip: String

    var id: String { dateID }
}

struct DetailedDailyBarChart: View {
    let values: [DetailDailyValue]
    let color: Color
    @State private var hoveredEntryID: String?

    private var hoveredEntry: DetailDailyValue? {
        values.first { $0.id == hoveredEntryID }
    }

    var body: some View {
        GeometryReader { proxy in
            let tooltipHeight: CGFloat = 46
            let tooltipWidth: CGFloat = 164
            let gap: CGFloat = 6
            let barAreaHeight = max(3, proxy.size.height - tooltipHeight - gap)
            let axisHeight: CGFloat = 16
            let axisGap: CGFloat = 3
            let plotHeight = max(3, barAreaHeight - axisHeight - axisGap)
            let maximum = max(values.map(\.value).max() ?? 0, 1)
            let spacing: CGFloat = values.count > 14 ? 2 : 4
            let width = max(3, (proxy.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))

            VStack(spacing: gap) {
                ZStack(alignment: .topLeading) {
                    if let hoveredEntry,
                       let index = values.firstIndex(where: { $0.id == hoveredEntry.id }) {
                        // Keep the bubble in the reserved tooltip lane. It
                        // follows the hovered column horizontally, but can
                        // neither escape the card nor overlap any columns.
                        let columnCenter = CGFloat(index) * (width + spacing) + width / 2
                        let tooltipCenter = min(
                            max(tooltipWidth / 2, columnCenter),
                            max(tooltipWidth / 2, proxy.size.width - tooltipWidth / 2)
                        )
                        Text(hoveredEntry.tooltip)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(width: tooltipWidth, height: tooltipHeight, alignment: .leading)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
                            .position(x: tooltipCenter, y: tooltipHeight / 2)
                    } else {
                        Text(StatsL10n.text("statistics.chart.hover_hint"))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(height: tooltipHeight)

                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(values) { entry in
                            dailyBar(
                                entry,
                                width: width,
                                height: max(3, plotHeight * CGFloat(entry.value / maximum))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: plotHeight, alignment: .bottom)

                    dateAxis(
                        totalWidth: proxy.size.width,
                        plotHeight: plotHeight,
                        axisGap: axisGap,
                        axisHeight: axisHeight,
                        columnWidth: width,
                        spacing: spacing
                    )
                }
                .frame(height: barAreaHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(StatsL10n.text("statistics.chart.daily_trend"))
    }

    private func dailyBar(_ entry: DetailDailyValue, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(3, width / 2))
            .fill(entry.value > 0 ? color.opacity(0.84) : Color.secondary.opacity(0.14))
            .frame(width: width, height: height)
            .onHover { updateHover(for: entry, isHovering: $0) }
            .accessibilityLabel(entry.tooltip)
    }

    private func dateAxis(
        totalWidth: CGFloat,
        plotHeight: CGFloat,
        axisGap: CGFloat,
        axisHeight: CGFloat,
        columnWidth: CGFloat,
        spacing: CGFloat
    ) -> some View {
        let labelWidth: CGFloat = 34
        return ZStack(alignment: .topLeading) {
            ForEach(dateTickIndices, id: \.self) { index in
                let columnCenter = CGFloat(index) * (columnWidth + spacing) + columnWidth / 2
                let labelCenter = min(
                    max(labelWidth / 2, columnCenter),
                    max(labelWidth / 2, totalWidth - labelWidth / 2)
                )
                Text(shortDate(values[index].dateID))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth)
                    .position(x: labelCenter, y: plotHeight + axisGap + axisHeight / 2)
            }
        }
    }

    private var dateTickIndices: [Int] {
        guard !values.isEmpty else { return [] }
        if values.count <= 7 { return Array(values.indices) }

        let tickStride = values.count <= 14 ? 3 : 5
        var indices = Array(stride(from: 0, to: values.count, by: tickStride))
        if indices.last != values.count - 1 {
            indices.append(values.count - 1)
        }
        return indices
    }

    private func shortDate(_ dateID: String) -> String {
        let parts = dateID.split(separator: "-")
        guard parts.count == 3 else { return dateID }
        return "\(parts[1])/\(parts[2])"
    }

    private func updateHover(for entry: DetailDailyValue, isHovering: Bool) {
        if isHovering {
            hoveredEntryID = entry.id
        } else if hoveredEntryID == entry.id {
            hoveredEntryID = nil
        }
    }
}
