import SwiftUI

/// A deliberately slowed visual cue for fan activity. It is not a literal RPM
/// rendering: physical fan speeds would be too fast to perceive at dashboard
/// size, so the rotation maps the reported percentage into a readable range.
struct DashboardFanRotor: View {
    let fraction: Double
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedFraction: Double {
        min(1, max(0, fraction))
    }

    private var visualRevolutionsPerSecond: Double {
        // Keep low-speed fans visibly alive while making high-speed changes
        // easy to distinguish without turning the icon into a blur.
        0.25 + clampedFraction * 1.75
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

            if reduceMotion || clampedFraction == 0 {
                rotor
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
                    let angle = (timeline.date.timeIntervalSinceReferenceDate * visualRevolutionsPerSecond * 360)
                        .truncatingRemainder(dividingBy: 360)
                    rotor.rotationEffect(.degrees(angle))
                }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
