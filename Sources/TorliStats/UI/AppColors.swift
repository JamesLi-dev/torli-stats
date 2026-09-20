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

    // Semantic status tokens use slightly brighter dark-mode variants so
    // status remains legible on the dashboard's dark card surfaces.
    static let accent = adaptive(
        light: NSColor(calibratedRed: 0.25, green: 0.56, blue: 0.94, alpha: 1),
        dark: NSColor(calibratedRed: 0.38, green: 0.66, blue: 1.0, alpha: 1)
    )
    static let activity = adaptive(
        light: NSColor(calibratedRed: 0.72, green: 0.38, blue: 0.88, alpha: 1),
        dark: NSColor(calibratedRed: 0.78, green: 0.50, blue: 0.96, alpha: 1)
    )
    static let success = adaptive(
        light: NSColor(calibratedRed: 0.17, green: 0.72, blue: 0.40, alpha: 1),
        dark: NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.51, alpha: 1)
    )
    static let caution = adaptive(
        light: NSColor(calibratedRed: 0.86, green: 0.65, blue: 0.16, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.74, blue: 0.28, alpha: 1)
    )
    static let warning = adaptive(
        light: NSColor(calibratedRed: 0.92, green: 0.57, blue: 0.16, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.25, alpha: 1)
    )
    static let critical = adaptive(
        light: NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.28, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.43, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}