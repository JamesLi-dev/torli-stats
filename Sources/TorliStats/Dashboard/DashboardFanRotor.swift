import SwiftUI

/// A deliberately slowed visual cue for fan activity. It is not a literal RPM
/// rendering: physical fan speeds would be too fast to perceive at dashboard
/// size, so the rotation maps the reported percentage into a readable range.
struct DashboardFanRotor: View {
    let fraction: Double
    let tint: Color

    @State private var isHovered = false

    private var clampedFraction: Double {
        min(1, max(0, fraction))
    }

    private var rotor: some View {
        Image(systemName: "fanblades.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 2.3)
            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Keep the indicator static during normal monitoring. Hovering
            // provides a small interaction cue without a continuous redraw.
            rotor
                .rotationEffect(.degrees(isHovered ? 28 : 0))
                .animation(.easeOut(duration: 0.18), value: isHovered)
        }
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .accessibilityHidden(true)
    }
}
