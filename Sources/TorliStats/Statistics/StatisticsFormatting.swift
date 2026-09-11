import Foundation

enum StatisticsFormatting {
    static func tokenCount(_ value: Double) -> String {
        let isChinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
        let units: [(Double, String)] = isChinese
            ? [(100_000_000, "亿"), (10_000, "万")]
            : [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        if let (divisor, suffix) = units.first(where: { value >= $0.0 }) {
            return (value / divisor).formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) + suffix
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    static func compactNumber(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : String(value)
    }

    static func compactNumber(_ value: Double) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        default: return String(Int(value))
        }
    }

    static func compactDuration(_ seconds: Double) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? StatsL10n.format("statistics.duration", minutes / 60, minutes % 60) : StatsL10n.format("statistics.minutes", minutes)
    }

    static func dateRangeText(_ dateIDs: [String]) -> String? {
        guard let first = dateIDs.first, let last = dateIDs.last else { return nil }
        return "\(first) — \(last)"
    }
}
