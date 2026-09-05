import SwiftUI

struct CPUBarChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = values.count > 16 ? 1 : 2
            let barWidth = max(1, (geometry.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: min(2, barWidth / 2))
                        .fill(Color.green.opacity(0.9))
                        .frame(width: barWidth, height: max(2, geometry.size.height * CGFloat(min(100, max(0, value)) / 100)))
                        .help("核心 \(index + 1)：\(Int(value))%")
                        .accessibilityLabel("核心 \(index + 1)")
                        .accessibilityValue("\(Int(value))%")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(values.max() ?? 1, 1)
            let minValue = values.min() ?? 0
            let range = max(maxValue - minValue, 1)

            Path { path in
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let y = geometry.size.height * (1 - CGFloat((value - minValue) / range))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct TypingTrendSparkline: View {
    let records: [TypingDailyRecord]

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(records.map(\.keyCount).max() ?? 0, 1)
            let spacing: CGFloat = records.count > 10 ? 2 : 3
            let width = max(2, (geometry.size.width - spacing * CGFloat(max(records.count - 1, 0))) / CGFloat(max(records.count, 1)))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(records) { record in
                    RoundedRectangle(cornerRadius: min(2, width / 2))
                        .fill(record.keyCount == 0 ? Color.secondary.opacity(0.16) : Color.cyan.opacity(0.82))
                        .frame(width: width, height: max(2, geometry.size.height * CGFloat(record.keyCount) / CGFloat(maximum)))
                        .accessibilityLabel(record.dateID)
                        .accessibilityValue("\(record.keyCount) 键")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct NetworkChart: View {
    let download: [Double]
    let upload: [Double]

    var body: some View {
        ZStack {
            Sparkline(values: download, color: .cyan)
            Sparkline(values: upload, color: .green)
        }
    }
}
