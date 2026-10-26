import AppKit
import SwiftUI

enum CodexStatusMetric: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: return StatsL10n.text("codex.metric.remaining")
        case .used: return StatsL10n.text("codex.metric.used")
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
        case .defaultAccount: return StatsL10n.text("codex.status_mode.default_account")
        case .lowestRemaining: return StatsL10n.text("codex.status_mode.lowest_remaining")
        case .eachAccount: return StatsL10n.text("codex.status_mode.each_account")
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
        case .system: return StatsL10n.text("status_group.system")
        case .network: return StatsL10n.text("status_group.network")
        case .typing: return StatsL10n.text("status_group.typing")
        case .codex: return StatsL10n.text("status_group.codex")
        case .logo: return StatsL10n.text("status_group.logo")
        }
    }
}

enum SystemStatusBarStyle: String, CaseIterable, Identifiable {
    case compact
    case stacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return StatsL10n.text("settings.status_bar.layout_vertical")
        case .stacked: return StatsL10n.text("settings.status_bar.layout_horizontal")
        }
    }
}

enum StatusBarFontSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .small: return 8
        case .standard: return 9
        case .large: return 10
        }
    }

    var title: String {
        switch self {
        case .small: return StatsL10n.text("status_bar.font.small")
        case .standard: return StatsL10n.text("status_bar.font.standard")
        case .large: return StatsL10n.text("status_bar.font.large")
        }
    }
}

enum NetworkRateUnit: String, CaseIterable, Identifiable {
    case automatic
    case kilobytes
    case megabytes
    case megabits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return StatsL10n.text("settings.status_bar.network_unit_auto")
        case .kilobytes: return "KB/s"
        case .megabytes: return "MB/s"
        case .megabits: return "Mbps"
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
        case .system: return StatsL10n.text("theme.system")
        case .light: return StatsL10n.text("theme.light")
        case .dark: return StatsL10n.text("theme.dark")
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
        case .compact: return StatsL10n.text("display.compact")
        case .standard: return StatsL10n.text("display.standard")
        case .detailed: return StatsL10n.text("display.detailed")
        }
    }
}

enum DashboardModule: Hashable, RawRepresentable, CaseIterable, Codable, Identifiable {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case networkApplications
    case fan
    case typing
    case power
    case codex
    case wakatime
    case feature(String)
    case processes

    static var allCases: [DashboardModule] {
        [.cpu, .gpu, .memory, .disk, .network, .networkApplications, .fan, .typing, .power, .codex, .wakatime, .processes] + FeatureRegistry.shared.features.map { .feature($0.id) }
    }
    var rawValue: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "gpu"
        case .memory: return "memory"
        case .disk: return "disk"
        case .network: return "network"
        case .networkApplications: return "networkApplications"
        case .fan: return "fan"
        case .typing: return "typing"
        case .power: return "power"
        case .codex: return "codex"
        case .wakatime: return "wakatime"
        case .processes: return "processes"
        case .feature(let id): return "feature:" + id
        }
    }
    init?(rawValue: String) {
        switch rawValue {
        case "cpu": self = .cpu
        case "gpu": self = .gpu
        case "memory": self = .memory
        case "disk": self = .disk
        case "network": self = .network
        case "networkApplications": self = .networkApplications
        case "fan": self = .fan
        case "typing": self = .typing
        case "power": self = .power
        case "codex": self = .codex
        case "wakatime": self = .wakatime
        case "processes": self = .processes
        default:
            let id = rawValue.hasPrefix("feature:") ? String(rawValue.dropFirst(8)) : rawValue
            guard FeatureRegistry.shared.feature(id) != nil else { return nil }
            self = .feature(id)
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let module = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown dashboard module")
        }
        self = module
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return StatsL10n.text("module.memory")
        case .disk: return StatsL10n.text("module.disk")
        case .network: return StatsL10n.text("module.network")
        case .networkApplications: return StatsL10n.text("module.network_applications")
        case .fan: return StatsL10n.text("module.fan")
        case .typing: return StatsL10n.text("module.typing")
        case .power: return StatsL10n.text("module.power")
        case .codex: return "Codex"
        case .wakatime: return "WakaTime"
        case .feature(let id): return FeatureRegistry.shared.feature(id)?.title ?? id
        case .processes: return StatsL10n.text("module.processes")
        }
    }

    var isMetric: Bool {
        switch self {
        case .cpu, .gpu, .memory, .disk, .network, .fan, .typing: return true
        case .power, .codex, .wakatime, .feature, .processes, .networkApplications: return false
        }
    }
}

enum ProcessSortOption: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return StatsL10n.text("module.memory")
        case .combined: return StatsL10n.text("process.display.combined")
        }
    }
}
