import AppKit
import SwiftUI

enum AppColors {
    // 同时适配系统亮色/暗色，并让背景与卡片保持轻微层次。
    static let backgroundNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.075, green: 0.070, blue: 0.060, alpha: 1)
            : NSColor(calibratedRed: 0.93, green: 0.925, blue: 0.90, alpha: 1)
    }
    static let background = Color(nsColor: backgroundNSColor)
    static let card = adaptive(
        light: NSColor(calibratedRed: 0.985, green: 0.98, blue: 0.95, alpha: 1),
        dark: NSColor(calibratedRed: 0.165, green: 0.155, blue: 0.125, alpha: 1)
    )
    static let badge = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
