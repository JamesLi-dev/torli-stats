import Foundation

/// Localization entry point for Torli Stats UI. Notes keeps its own table so
/// existing Notes translation keys remain stable while the application adopts a
/// single display-language preference.
enum StatsL10n {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: "Stats")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}
