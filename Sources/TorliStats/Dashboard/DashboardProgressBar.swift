import SwiftUI

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

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * clampedValue)
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
