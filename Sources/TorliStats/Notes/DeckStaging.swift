import SwiftUI
import AppKit

// MARK: - Staging (the 45 ms shingle)

private struct Staged: ViewModifier {
    let index: Int
    let totalCount: Int
    let revealed: Bool
    let onRight: Bool

    func body(content: Content) -> some View {
        let delay = revealed
            ? Double(index) * 0.042
            : Double(max(0, totalCount - 1 - index)) * 0.030
        content
            .offset(x: revealed ? 0 : (onRight ? DeckGeom.tabWidth + 24 : -(DeckGeom.tabWidth + 24)))
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.84)
                        .delay(delay), value: revealed)
    }
}

extension View {
    func staged(index: Int, total: Int = 1, revealed: Bool, onRight: Bool) -> some View {
        modifier(Staged(index: index, totalCount: total, revealed: revealed, onRight: onRight))
    }
}

struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
