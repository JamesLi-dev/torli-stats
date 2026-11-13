import Foundation
import Security
import TorliStatsShared

enum SensorHelperRepairReason: Equatable {
    case invalidSignature
    case changedApp
    case incompatibleProtocol
    case connectionUnavailable

    var message: String {
        switch self {
        case .invalidSignature: return StatsL10n.text("sensor.repair.invalid_signature")
        case .changedApp: return StatsL10n.text("sensor.repair.changed_app")
        case .incompatibleProtocol: return StatsL10n.text("sensor.operation.incompatible")
        case .connectionUnavailable: return StatsL10n.text("sensor.repair.connection_unavailable")
        }
    }
}

struct SensorHelperInstallationStatus {
    let isInstalled: Bool
    let signatureIsValid: Bool
    let clientIsAuthorized: Bool
    let signatureMessage: String

    func repairReason(isReachable: Bool, protocolVersion: Int?, retriesRemaining: Int) -> SensorHelperRepairReason? {
        guard isInstalled else { return nil }
        if !signatureIsValid { return .invalidSignature }
        if isReachable, protocolVersion != SensorServiceConstants.protocolVersion { return .incompatibleProtocol }
        if !clientIsAuthorized { return .changedApp }
        if !isReachable, retriesRemaining == 0 { return .connectionUnavailable }
        return nil
    }

    static func inspect() -> Self {
        let helperPath = SensorServiceConstants.installedHelperPath
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return Self(
                isInstalled: false,
                signatureIsValid: false,
                clientIsAuthorized: false,
                signatureMessage: StatsL10n.text("sensor.signature.helper_not_found")
            )
        }

        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(URL(fileURLWithPath: helperPath) as CFURL, [], &code)
        let signatureIsValid = created == errSecSuccess && code.map {
            SecStaticCodeCheckValidity($0, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
        } == true
        let clientIsAuthorized = installedClientRequirement().map(currentProcessMatches) ?? false
        return Self(
            isInstalled: true,
            signatureIsValid: signatureIsValid,
            clientIsAuthorized: clientIsAuthorized,
            signatureMessage: StatsL10n.text(!signatureIsValid
                ? "sensor.signature.verification_failed"
                : (clientIsAuthorized ? "sensor.signature.verified" : "sensor.repair.changed_app"))
        )
    }

    /// Mirror the helper's root-owned requirement check without changing its
    /// authorization policy. A new ad-hoc build has a different code hash.
    private static func installedClientRequirement() -> String? {
        let path = SensorServiceConstants.clientRequirementPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              permissions & 0o022 == 0 else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    static func currentProcessMatches(_ requirementText: String) -> Bool {
        var requirement: SecRequirement?
        var code: SecCode?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
