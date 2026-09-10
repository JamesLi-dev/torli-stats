import AppKit

struct StatusBarLogoConfiguration: Equatable {
    let isVisible: Bool
    let runner: StatusBarRunner
    let acceleratesWithCPU: Bool
    let reduceMotion: Bool
}

struct StatusLine {
    let cpu: String
    let memory: String
    /// Raw bytes per second. Formatting belongs to the status-bar preferences,
    /// so changing units or precision updates immediately without resampling.
    let download: Double
    let upload: Double
}
