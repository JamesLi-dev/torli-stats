import AppKit
import SwiftUI

enum AppColors {
    // Neutral, system-like surfaces avoid a separate warm palette in each
    // window. The small luminance steps retain hierarchy without making the
    // sidebar and content area look like unrelated panels.
    static let backgroundNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.115, alpha: 1)
            : NSColor(calibratedRed: 0.955, green: 0.955, blue: 0.965, alpha: 1)
    }
    static let background = Color(nsColor: backgroundNSColor)
    // A translucent neutral veil keeps the wallpaper-backed glass bright and
    // avoids warm/grey wallpaper colours tinting Settings surfaces.
    static let settingsGlassTint = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.30),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.055)
    )
    static let card = adaptive(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.78),
        dark: NSColor(calibratedRed: 0.155, green: 0.155, blue: 0.170, alpha: 0.82)
    )
    static let badge = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.075),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}
