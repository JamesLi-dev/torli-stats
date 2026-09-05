import AppKit
import SwiftUI

enum CodexStatusMetric: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: return "剩余量"
        case .used: return "用量"
        }
    }
}

enum CodexStatusBarMode: String, CaseIterable, Identifiable {
    case defaultAccount
    case lowestRemaining
    case eachAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultAccount: return "默认账号"
        case .lowestRemaining: return "最低剩余"
        case .eachAccount: return "逐账号"
        }
    }
}

enum StatusBarMetricGroup: String, CaseIterable, Codable, Identifiable {
    case system
    case network
    case typing
    case codex
    case logo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统（CPU / 内存）"
        case .network: return "网络（下载 / 上传）"
        case .typing: return "输入统计"
        case .codex: return "Codex 使用情况"
        case .logo: return "状态栏 Logo"
        }
    }
}

enum SystemStatusBarStyle: String, CaseIterable, Identifiable {
    case compact
    case stacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .stacked: return "分栏"
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var windowAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum DashboardDensity: String, CaseIterable, Identifiable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .detailed: return "详细"
        }
    }
}

enum DashboardModule: String, CaseIterable, Codable, Identifiable {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case fan
    case typing
    case power
    case codex
    case wakatime
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "内存"
        case .disk: return "磁盘"
        case .network: return "网络"
        case .fan: return "风扇"
        case .typing: return "输入"
        case .power: return "电源"
        case .codex: return "Codex"
        case .wakatime: return "WakaTime"
        case .processes: return "进程"
        }
    }

    var isMetric: Bool {
        switch self {
        case .cpu, .gpu, .memory, .disk, .network, .fan, .typing: return true
        case .power, .codex, .wakatime, .processes: return false
        }
    }
}

enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        }
    }
}
