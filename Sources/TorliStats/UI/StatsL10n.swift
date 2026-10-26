import Foundation

/// Localization entry point for Torli Stats UI. Notes keeps its own table so
/// existing Notes translation keys remain stable while the application adopts a
/// single display-language preference.
public enum StatsL10n {
    public static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: "Stats")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}
