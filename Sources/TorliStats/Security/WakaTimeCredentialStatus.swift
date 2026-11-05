import Foundation
import Security

/// UI hint only: never authorizes requests or proves a token is readable/valid.
enum WakaTimeCredentialHint: String {
    case unknown, configured, notConfigured
    static let defaultsKey = "wakatimeCredentialConfigurationHint"
    static func load(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .unknown
    }
    func save(to defaults: UserDefaults) { defaults.set(rawValue, forKey: Self.defaultsKey) }
}

enum WakaTimeCredentialFailure {
    static func message(for error: Error) -> String {
        if case CredentialVaultError.malformed = error {
            return StatsL10n.text("wakatime.credential_malformed")
        }
        if case CredentialVaultError.unavailable(let status) = error,
           [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed].contains(status) {
            return StatsL10n.text("wakatime.credential_authorization_required")
        }
        return StatsL10n.text("wakatime.credential_unavailable")
    }
}
