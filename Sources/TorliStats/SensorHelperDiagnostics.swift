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
                signatureMessage: "未找到已安装的辅助进程。"
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
                signatureMessage: task.terminationStatus == 0 ? "辅助进程签名已验证。" : "辅助进程签名验证失败。"
            )
        } catch {
            return Self(
                isInstalled: true,
                signatureIsValid: false,
                signatureMessage: "无法验证辅助进程签名。"
            )
        }
    }
}
