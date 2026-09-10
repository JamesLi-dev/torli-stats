import Foundation
import TorliStatsShared

struct SensorHelperInstallationStatus {
    let isInstalled: Bool
    let signatureIsValid: Bool
    let signatureMessage: String

    static func inspect() -> Self {
        let helperPath = SensorServiceConstants.installedHelperPath
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return Self(
                isInstalled: false,
                signatureIsValid: false,
                signatureMessage: StatsL10n.text("sensor.signature.helper_not_found")
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--verify", "--deep", "--strict", helperPath]
        do {
            try task.run()
            task.waitUntilExit()
            return Self(
                isInstalled: true,
                signatureIsValid: task.terminationStatus == 0,
                signatureMessage: task.terminationStatus == 0 ? StatsL10n.text("sensor.signature.verified") : StatsL10n.text("sensor.signature.verification_failed")
            )
        } catch {
            return Self(
                isInstalled: true,
                signatureIsValid: false,
                signatureMessage: StatsL10n.text("sensor.signature.unable_to_verify")
            )
        }
    }
}
