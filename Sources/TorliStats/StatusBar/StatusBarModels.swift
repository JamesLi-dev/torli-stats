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
    let download: String
    let upload: String
}
