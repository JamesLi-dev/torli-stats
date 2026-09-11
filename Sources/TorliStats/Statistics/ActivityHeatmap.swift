import SwiftUI

struct ActivityDay: Identifiable, Codable, Equatable {
    let dateID: String
    let value: Double
    var id: String { dateID }
}

/// Shared calendar layout. Missing observations stay distinct from measured zeroes.
struct ActivityHeatmap: View {
    enum Range {
        case sixMonths
        case year
    }

    let title: String
    let records: [ActivityDay]
    var color: Color = .purple
    var compact = false
    var range: Range = .year
    var formatValue: (Double) -> String
    @State private var mode = 0
    @State private var hoveredDay: String?
    @State private var hoveredColumn: Int?

    @State private var preparedDates: [Date] = []
    @State private var preparedValues: [String: Double] = [:]
    @State private var preparedHeights: [Int] = []
    @State private var preparedMaximum = 1.0

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    static func dateID(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        let first: Date
        switch range {
        case .sixMonths:
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: today)!
            first = calendar.date(byAdding: .day, value: 1, to: sixMonthsAgo)!
        case .year:
            first = calendar.date(byAdding: .day, value: -364, to: today)!
        }
        let start = calendar.dateInterval(of: .weekOfYear, for: first)!.start
        let count = calendar.dateComponents([.day], from: start, to: today).day! + 1
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private func prepare() {
        let dates = days
        let raw = Dictionary(records.map { ($0.dateID, $0.value) }, uniquingKeysWith: +)
        var data: [String: Double] = [:]
        var cumulative = 0.0
        for column in 0..<((dates.count + 6) / 7) {
            let week = dates[(column * 7)..<min(column * 7 + 7, dates.count)]
            let total = week.reduce(0) { $0 + (raw[Self.dateID($1)] ?? 0) }
            cumulative += total
            for date in week {
                let id = Self.dateID(date)
                data[id] = mode == 0 ? raw[id] : (mode == 1 ? total : cumulative)
            }
        }
        preparedDates = dates
        preparedValues = data
        preparedHeights = columnHeights(for: dates, raw: raw)
        preparedMaximum = max(data.values.max() ?? 0, 1)
    }

    private func columnHeights(for dates: [Date], raw: [String: Double]) -> [Int] {
        var totals: [Double] = []
        var cumulative = 0.0
        for column in 0..<((dates.count + 6) / 7) {
            let start = column * 7
            let end = min(start + 7, dates.count)
            let total = dates[start..<end].reduce(0) { $0 + (raw[Self.dateID($1)] ?? 0) }
            if mode == 2 { cumulative += total }
            totals.append(mode == 2 ? cumulative : total)
        }
        let maximum = max(totals.max() ?? 0, 1)
        return totals.map { value in
            guard value > 0 else { return 0 }
            return min(7, max(1, Int(ceil(value / maximum * 7))))
        }
    }

    var body: some View {
        let dates = preparedDates
        let data = preparedValues
        let maximum = preparedMaximum
        let columnCount = max(1, (dates.count + 6) / 7)
        let heights = preparedHeights
        VStack(alignment: .leading, spacing: compact ? 2 : 9) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 4)
                ForEach(0..<3) { index in
                    Button(StatsL10n.text(["activity.daily", "activity.weekly", "activity.cumulative"][index])) {
                        mode = index
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(mode == index ? .primary : .secondary)
                }
            }
            Text(hoveredDetail(data: data, dates: dates))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.vertical, compact ? 2 : 0)
            GeometryReader { geometry in
                let gap: CGFloat = compact ? 1.5 : 3
                let size = max(2, (geometry.size.width - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let index = column * 7 + row
                                if !dates.isEmpty && (mode != 0 || index < dates.count) {
                                    let id = Self.dateID(dates[min(index, dates.count - 1)])
                                    let isHovered = mode == 0 && hoveredDay == id
                                    RoundedRectangle(cornerRadius: min(size / 2, compact ? 3 : 4))
                                        .fill(mode == 0
                                            ? fill(data[id], maximum: maximum)
                                            : barFill(column: column, row: row, heights: heights))
                                        .overlay(RoundedRectangle(cornerRadius: min(size / 2, compact ? 3 : 4)).strokeBorder(Color.secondary.opacity(data[id] == nil ? 0.18 : 0), lineWidth: 0.5))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: min(size / 2, compact ? 3 : 4))
                                                .fill(isHovered ? color.opacity(0.12) : .clear)
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: min(size / 2, compact ? 3 : 4))
                                                        .strokeBorder(isHovered ? color.opacity(0.9) : .clear, lineWidth: 1.5)
                                                }
                                                .allowsHitTesting(false)
                                        }
                                        .frame(width: size, height: size)
                                        .contentShape(Rectangle())
                                        .onHover {
                                            guard mode == 0 else { return }
                                            if $0 {
                                                hoveredDay = id
                                            } else if hoveredDay == id {
                                                hoveredDay = nil
                                            }
                                        }
                                        .help(mode == 0 ? detail(for: id, data: data) : detail(forColumn: column, data: data, dates: dates))
                                        .accessibilityLabel(mode == 0 ? detail(for: id, data: data) : detail(forColumn: column, data: data, dates: dates))
                                } else {
                                    Color.clear.frame(width: size, height: size)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onHover {
                            guard mode != 0 else { return }
                            if $0 {
                                hoveredColumn = column
                            } else if hoveredColumn == column {
                                hoveredColumn = nil
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: compact ? 3 : 5, style: .continuous)
                                .fill(hoveredColumn == column ? color.opacity(0.10) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: compact ? 3 : 5, style: .continuous)
                                .stroke(hoveredColumn == column ? color.opacity(0.30) : .clear, lineWidth: 1)
                        )
                    }
                }
                ForEach(0..<((dates.count + 6) / 7), id: \.self) { column in
                    let date = dates[column * 7]
                    if calendar.component(.day, from: date) <= 7 {
                        let labelWidth: CGFloat = compact ? 13 : 24
                        let x = min(CGFloat(column) * (size + gap), max(0, geometry.size.width - labelWidth))
                        let y: CGFloat = 7 * (size + gap) + 2
                        Text(date.formatted(.dateTime.month(.abbreviated)))
                            .font(.system(size: compact ? 7 : 10))
                            .foregroundStyle(.secondary)
                            .offset(x: x, y: y)
                    }
                }
            }
            .aspectRatio(CGFloat(columnCount) / 7, contentMode: .fit)
            // Month labels are positioned just below the seven cell rows.
            .padding(.bottom, compact ? 5 : 16)
            if !compact {
                HStack(spacing: 3) {
                    Text(StatsL10n.text("activity.less"))
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(mode == 0 ? fill(Double(level), maximum: 4) : barLegendFill(level))
                            .frame(width: 8, height: 8)
                    }
                    Text(StatsL10n.text("activity.more"))
                    Spacer()
                    Text(StatsL10n.text(range == .sixMonths ? "activity.six_months" : "activity.year"))
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: compact ? 9 : 11, design: .rounded))
        .onAppear { prepare() }
        .onChange(of: records) { _, _ in prepare() }
        .onChange(of: Self.dateID(Date()) + calendar.timeZone.identifier + String(describing: range)) { _, _ in prepare() }
        .onChange(of: mode) { _, _ in
            prepare()
            hoveredDay = nil
            hoveredColumn = nil
        }
    }

    private func fill(_ value: Double?, maximum: Double) -> Color {
        guard let value else { return Color.secondary.opacity(0.035) }
        guard value > 0 else { return Color.secondary.opacity(0.10) }
        let level = min(4, max(1, ceil(value / maximum * 4)))
        return color.opacity(0.20 + level * 0.20)
    }

    private func barFill(column: Int, row: Int, heights: [Int]) -> Color {
        guard column < heights.count else { return Color.secondary.opacity(0.10) }
        guard heights[column] > 0, row >= 7 - heights[column] else {
            return Color.secondary.opacity(0.10)
        }
        return barColor(forHeight: heights[column])
    }

    private func barLegendFill(_ level: Int) -> Color {
        guard level > 0 else { return Color.secondary.opacity(0.10) }
        let height = Int(ceil(Double(level) / 4 * 7))
        return barColor(forHeight: height)
    }

    private func barColor(forHeight height: Int) -> Color {
        let opacity = 0.20 + Double(min(7, max(1, height))) / 7 * 0.68
        return color.opacity(opacity)
    }

    private func detail(for id: String, data: [String: Double]) -> String {
        let value = data[id].map(formatValue) ?? StatsL10n.text("activity.no_data")
        let scope = StatsL10n.text(["activity.daily", "activity.weekly", "activity.cumulative"][mode])
        return "\(id) · \(scope) · \(value)"
    }

    private func hoveredDetail(data: [String: Double], dates: [Date]) -> String {
        guard !dates.isEmpty else { return StatsL10n.text("activity.no_data") }
        if mode == 0 {
            return detail(for: hoveredDay ?? Self.dateID(Date()), data: data)
        }
        let column = hoveredColumn ?? max(0, (dates.count - 1) / 7)
        return detail(forColumn: column, data: data, dates: dates)
    }

    private func detail(forColumn column: Int, data: [String: Double], dates: [Date]) -> String {
        let startIndex = min(max(column, 0) * 7, max(0, dates.count - 1))
        let endIndex = min(startIndex + 6, dates.count - 1)
        let startID = Self.dateID(dates[startIndex])
        let value = data[startID].map(formatValue) ?? StatsL10n.text("activity.no_data")
        if mode == 1 {
            return StatsL10n.format("activity.week_tooltip", localizedDate(dates[startIndex]), localizedDate(dates[endIndex]), value)
        }
        return StatsL10n.format("activity.cumulative_tooltip", localizedDate(dates[endIndex]), value)
    }

    private func localizedDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day())
    }
}
