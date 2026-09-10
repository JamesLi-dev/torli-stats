import Foundation

/// Application-wide display language. `system` defers to the Mac's preferred
/// language order; explicit choices are persisted in the app's `AppleLanguages`
/// domain so AppKit and SwiftUI resolve the same localization after relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system: return StatsL10n.text("language.system")
        case .english: return StatsL10n.text("language.english")
        case .simplifiedChinese: return StatsL10n.text("language.simplified_chinese")
        }
    }

    var appleLanguageIdentifier: String? {
        self == .system ? nil : rawValue
    }

    static func resolve(_ identifiers: [String]?) -> AppLanguage {
        guard let identifier = identifiers?.first?.lowercased() else { return .system }
        if identifier.hasPrefix("en") { return .english }
        if identifier == "zh" || identifier.hasPrefix("zh-hans")
            || identifier.hasPrefix("zh-cn") || identifier.hasPrefix("zh-sg") {
            return .simplifiedChinese
        }
        return .system
    }
}

enum AppLanguageSettings {
    private static let defaults = UserDefaults.standard
    private static let applicationDomain = Bundle.main.bundleIdentifier ?? "local.torli.stats"

    static var language: AppLanguage {
        get {
            let identifiers = defaults.persistentDomain(forName: applicationDomain)?["AppleLanguages"]
                as? [String]
            return AppLanguage.resolve(identifiers)
        }
        set {
            if let identifier = newValue.appleLanguageIdentifier {
                defaults.set([identifier], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }
}
