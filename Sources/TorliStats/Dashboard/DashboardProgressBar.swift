import SwiftUI

enum DashboardPalette {
    static let cpuBars = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.84, blue: 0.50),
            Color(red: 0.15, green: 0.68, blue: 0.36)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let inputBars = LinearGradient(
        colors: [
            Color(red: 0.34, green: 0.68, blue: 0.98),
            Color(red: 0.20, green: 0.48, blue: 0.90)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let diskProgress = Color(red: 0.25, green: 0.56, blue: 0.94)
    static let quotaSuccess = Color(red: 0.17, green: 0.72, blue: 0.40)
    static let quotaWarning = Color(red: 0.92, green: 0.57, blue: 0.16)
    static let quotaCritical = Color(red: 0.88, green: 0.25, blue: 0.28)
}

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

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.76), tint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fillGradient)
                        .frame(width: proxy.size.width * clampedValue)
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        }
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
