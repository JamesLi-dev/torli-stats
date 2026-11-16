import Foundation
import CryptoKit
import CommonCrypto
import Security

/// The archive contains explicitly listed community preferences, the login
/// item intent, and the WakaTime OAuth token; other user data is never touched.
enum SettingsBackup {
    enum BackupError: Error { case invalidPassword, invalidFile, cryptography, launchUnavailable, launchRestoreFailed, rollbackFailed }
    private static let iterations: UInt32 = 600_000
    private static let magic = Data("TORLIBK1".utf8)
    private static let maxSize = 4 * 1024 * 1024
    private static let maxFileSize = maxSize + 52

    static func readFile(at url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maxFileSize {
            guard let chunk = try file.read(upToCount: min(64 * 1024, maxFileSize + 1 - data.count)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= maxFileSize else { throw BackupError.invalidFile }
        return data
    }

    private static let boolKeys = "showCPU showMemory showDownload showUpload showCPUCard showGPUCard showMemoryCard showDiskCard showNetworkCard showNetworkApplicationsCard showFanCard showTypingCard showPowerCard showProcessesCard showCodexCard showWakaTimeCard wakaTimeEnabled showDashboardDeviceInfo showTemperatureTags showProcessPID showCodexStatusItem showCPUTemperatureStatusItem showGPUTemperatureStatusItem showTypingStatusItem showStatusBarMetricIcons statusBarUsageColorsEnabled showStatusBarLogo statusBarLogoAnimated statusBarLogoAnimation privacyMode automaticUpdateChecks typingStatsEnabled codexAutoRefresh codexTokenActivityEnabled powerSavingMode manualMonitoringPaused backgroundMonitoringEnabled nightMonitoringPauseEnabled adaptiveSamplingEnabled lowBatterySavingEnabled notesDeckEnabled showOverFullScreen deckOnLeftEdge openOnHover tabPreview markdownStyling confineToSpace deckAlwaysShown deckPillHidden".split(separator: " ").map(String.init)
    private static let stringKeys = "themePreference wakaTimeRange dashboardDensity codexStatusMetric codexStatusBarMode systemStatusBarStyle statusBarFontSize networkRateUnit statusBarStaticLogo statusBarRunner codexDefaultAccountName codexHomePath processSort displayTarget noteFontName deckStyle dashboardSelectedTab".split(separator: " ").map(String.init)
    private static let numberKeys = "codexStatusBarAccountLimit networkRateDecimalPlaces codexRefreshInterval refreshInterval nightMonitoringPauseStartSeconds nightMonitoringPauseEndSeconds batteryRefreshInterval lowBatteryThreshold processLimit deckYRatio noteFontSize edgeWidth noteSizeIndex noteWidth floatingNoteW floatingNoteH deckScale notesLibrarySidebarWidth".split(separator: " ").map(String.init)
    private static let dataKeys = "codexManagedAccounts scNewNote scAllNotes scCapture scArchive scArchiveNote scClose scFind scTask scPin scColour scDelete scBigger scSmaller".split(separator: " ").map(String.init)
    private static let arrayKeys = ["dashboardModuleOrder", "statusBarMetricOrder", "AppleLanguages"]
    static let keys = boolKeys + stringKeys + numberKeys + dataKeys + arrayKeys

    struct Snapshot {
        let preferences: [String: Any]
        let wakaToken: String?
        let launchAtLogin: Bool
    }

    static func snapshot(domain: [String: Any], wakaToken: String?, launchAtLogin: Bool) -> Snapshot {
        Snapshot(preferences: domain.filter { keys.contains($0.key) }, wakaToken: wakaToken, launchAtLogin: launchAtLogin)
    }

    static func encode(_ snapshot: Snapshot, password: String) throws -> Data {
        guard !password.isEmpty else { throw BackupError.invalidPassword }
        try validate(snapshot)
        var payload: [String: Any] = ["version": 2, "preferences": snapshot.preferences, "launchAtLogin": snapshot.launchAtLogin]
        if let token = snapshot.wakaToken { payload["wakaToken"] = token }
        let plaintext = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        guard plaintext.count <= maxSize else { throw BackupError.invalidFile }
        var salt = Data(count: 16)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else { throw BackupError.cryptography }
        let key = try derive(password, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: magic + salt)
        guard let combined = sealed.combined else { throw BackupError.cryptography }
        return magic + salt + combined
    }

    static func decode(_ data: Data, password: String) throws -> Snapshot {
        guard !password.isEmpty else { throw BackupError.invalidPassword }
        guard data.count >= 8 + 16 + 12 + 16, data.count <= maxSize + 52,
              data.prefix(8) == magic else { throw BackupError.invalidFile }
        let salt = data.subdata(in: 8..<24)
        let key = try derive(password, salt: salt)
        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data.subdata(in: 24..<data.count))
            plain = try AES.GCM.open(box, using: key, authenticating: magic + salt)
        } catch { throw BackupError.invalidFile }
        guard let object = try? PropertyListSerialization.propertyList(from: plain, options: [], format: nil),
              let payload = object as? [String: Any], Set(payload.keys).isSubset(of: ["version", "preferences", "wakaToken", "launchAtLogin"]),
              let version = payload["version"] as? Int, version == 2,
              let prefs = payload["preferences"] as? [String: Any],
              let launch = payload["launchAtLogin"] as? NSNumber, CFGetTypeID(launch) == CFBooleanGetTypeID(),
              payload["wakaToken"] == nil || payload["wakaToken"] is String else { throw BackupError.invalidFile }
        let snapshot = Snapshot(preferences: prefs, wakaToken: payload["wakaToken"] as? String, launchAtLogin: launch.boolValue)
        try validate(snapshot)
        return snapshot
    }

    private static func validate(_ snapshot: Snapshot) throws {
        guard Set(snapshot.preferences.keys).isSubset(of: Set(keys)),
              snapshot.wakaToken.map({ !$0.isEmpty && !$0.contains(where: { $0.isWhitespace || $0.isNewline }) }) ?? true else { throw BackupError.invalidFile }
        for (key, value) in snapshot.preferences {
            if boolKeys.contains(key) {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw BackupError.invalidFile }
            } else if numberKeys.contains(key) {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw BackupError.invalidFile }
            } else if stringKeys.contains(key) {
                guard value is String else { throw BackupError.invalidFile }
            } else if arrayKeys.contains(key) {
                guard value is [String] else { throw BackupError.invalidFile }
            } else if dataKeys.contains(key) {
                guard let data = value as? Data else { throw BackupError.invalidFile }
                if key == "codexManagedAccounts" {
                    guard (try? JSONDecoder().decode([CodexAccountConfiguration].self, from: data)) != nil else { throw BackupError.invalidFile }
                } else {
                    guard (try? JSONDecoder().decode(Shortcut.self, from: data)) != nil else { throw BackupError.invalidFile }
                }
            }
        }
    }

    /// Call only after decode/validation. Preserve unknown domains and namespaces.
    static func restore(_ snapshot: Snapshot, defaults: UserDefaults, domainName: String,
                        readToken: () throws -> String?, readLaunch: () throws -> Bool,
                        writeLaunch: (Bool) throws -> Void, writeToken: (String?) throws -> Void) throws {
        try validate(snapshot)
        var domain = defaults.persistentDomain(forName: domainName) ?? [:]
        for key in keys { domain.removeValue(forKey: key) }
        domain.merge(snapshot.preferences) { _, new in new }
        domain[WakaTimeCredentialHint.defaultsKey] = snapshot.wakaToken == nil ? "notConfigured" : "configured"
        let previousToken = try readToken()
        let previousLaunch = try readLaunch()
        if previousLaunch != snapshot.launchAtLogin {
            do {
                try writeLaunch(snapshot.launchAtLogin)
            } catch {
                do { try writeLaunch(previousLaunch) }
                catch { throw BackupError.rollbackFailed }
                throw BackupError.launchRestoreFailed
            }
        }
        do {
            try writeToken(snapshot.wakaToken)
        } catch {
            var rollbackFailed = false
            do { try writeToken(previousToken) } catch { rollbackFailed = true }
            if previousLaunch != snapshot.launchAtLogin {
                do { try writeLaunch(previousLaunch) } catch { rollbackFailed = true }
            }
            if rollbackFailed { throw BackupError.rollbackFailed }
            throw error
        }
        defaults.setPersistentDomain(domain, forName: domainName)
    }

    private static func derive(_ password: String, salt: Data) throws -> SymmetricKey {
        let bytes = Array(password.utf8)
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { s in
                bytes.withUnsafeBytes { p in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: Int8.self), bytes.count,
                                         s.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                                         out.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.cryptography }
        return SymmetricKey(data: output)
    }
}
