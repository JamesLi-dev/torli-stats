import XCTest
@testable import TorliStats

final class SettingsBackupTests: XCTestCase {
    func testRoundTripAndRestorePreserveUnrelatedData() throws {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["showCPU": false, "notesDeckEnabled": false,
                                      "typingRecords": Data([7]), "pro.private": "keep",
                                      "processLimit": 10], forName: name)
        let source: [String: Any] = ["showCPU": true, "notesDeckEnabled": true,
                                      "deckScale": 1.25, "codexHomePath": "/Users/example/.codex",
                                      "scClose": try JSONEncoder().encode(Shortcut(keyCode: 53, modifiers: 0)),
                                      "dashboardModuleOrder": ["cpu", "memory"], "AppleLanguages": ["en"]]
        let original = SettingsBackup.snapshot(domain: source, wakaToken: "secret-token", launchAtLogin: true)
        let encrypted = try SettingsBackup.encode(original, password: "correct horse")
        XCTAssertFalse(encrypted.range(of: Data("secret-token".utf8)) != nil)
        let decoded = try SettingsBackup.decode(encrypted, password: "correct horse")
        var written: String?
        var login = false
        try SettingsBackup.restore(decoded, defaults: defaults, domainName: name, readToken: { nil },
                                   readLaunch: { login }, writeLaunch: { login = $0 }) { written = $0 }
        XCTAssertTrue(login)
        let result = defaults.persistentDomain(forName: name)!
        XCTAssertEqual(result["showCPU"] as? Bool, true)
        XCTAssertEqual(result["notesDeckEnabled"] as? Bool, true)
        XCTAssertEqual(result["deckScale"] as? Double, 1.25)
        XCTAssertEqual(result["codexHomePath"] as? String, "/Users/example/.codex")
        XCTAssertEqual(result["scClose"] as? Data, source["scClose"] as? Data)
        XCTAssertEqual(result["dashboardModuleOrder"] as? [String], ["cpu", "memory"])
        XCTAssertEqual(result["AppleLanguages"] as? [String], ["en"])
        XCTAssertNil(result["processLimit"])
        XCTAssertEqual(result["typingRecords"] as? Data, Data([7]))
        XCTAssertEqual(result["pro.private"] as? String, "keep")
        XCTAssertEqual(written, "secret-token")
    }

    func testWrongPasswordAndDamageNeverReachRestore() throws {
        let original = SettingsBackup.snapshot(domain: ["showCPU": true], wakaToken: nil, launchAtLogin: false)
        let encrypted = try SettingsBackup.encode(original, password: "password")
        XCTAssertThrowsError(try SettingsBackup.decode(encrypted, password: "wrong"))
        var damaged = encrypted
        damaged[damaged.count - 1] ^= 1
        XCTAssertThrowsError(try SettingsBackup.decode(damaged, password: "password"))
        XCTAssertThrowsError(try SettingsBackup.decode(Data(encrypted.prefix(20)), password: "password"))
        XCTAssertThrowsError(try SettingsBackup.decode(Data(), password: "password"))
    }

    func testRandomSaltAndNonceAndEmptyPassword() throws {
        let snapshot = SettingsBackup.snapshot(domain: [:], wakaToken: nil, launchAtLogin: false)
        XCTAssertThrowsError(try SettingsBackup.encode(snapshot, password: ""))
        let first = try SettingsBackup.encode(snapshot, password: "password")
        let second = try SettingsBackup.encode(snapshot, password: "password")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first[8..<24], second[8..<24])
        XCTAssertNotEqual(first[24..<36], second[24..<36])
    }

    func testCredentialFailureAndInvalidValuesDoNotChangeDefaults() throws {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["showCPU": false, "pro.private": "keep"], forName: name)
        let valid = SettingsBackup.snapshot(domain: ["showCPU": true], wakaToken: "token", launchAtLogin: false)
        enum Failure: Error { case denied }
        var values: [String?] = []
        XCTAssertThrowsError(try SettingsBackup.restore(valid, defaults: defaults, domainName: name, readToken: { "old" }, readLaunch: { false }, writeLaunch: { _ in }) { token in
            values.append(token)
            if values.count == 1 { throw Failure.denied }
        })
        XCTAssertEqual(values, ["token", "old"])
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["showCPU"] as? Bool, false)
        let invalid = SettingsBackup.Snapshot(preferences: ["showCPU": "yes"], wakaToken: nil, launchAtLogin: false)
        var called = false
        XCTAssertThrowsError(try SettingsBackup.restore(invalid, defaults: defaults, domainName: name, readToken: { nil }, readLaunch: { false }, writeLaunch: { _ in }) { _ in called = true })
        XCTAssertFalse(called)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["pro.private"] as? String, "keep")
    }

    func testRollbackFailureIsDistinguished() {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["showCPU": false], forName: name)
        enum Failure: Error { case denied }
        let snapshot = SettingsBackup.snapshot(domain: ["showCPU": true], wakaToken: nil, launchAtLogin: false)
        XCTAssertThrowsError(try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name, readToken: { "old" }, readLaunch: { false }, writeLaunch: { _ in }) { _ in throw Failure.denied }) { error in
            guard case SettingsBackup.BackupError.rollbackFailed = error else {
                return XCTFail("Expected rollback failure")
            }
        }
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["showCPU"] as? Bool, false)
    }

    func testLoginTransitionsAndUnchangedState() throws {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var login = false
        var writes: [Bool] = []
        for requested in [true, true, false] {
            let snapshot = SettingsBackup.snapshot(domain: [:], wakaToken: nil, launchAtLogin: requested)
            try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name,
                                       readToken: { nil }, readLaunch: { login },
                                       writeLaunch: { login = $0; writes.append($0) },
                                       writeToken: { _ in })
            XCTAssertEqual(login, requested)
        }
        XCTAssertEqual(writes, [true, false])
    }

    func testLoginFailureRollsBackWithoutWritingTokenOrPreferences() {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["showCPU": false], forName: name)
        let snapshot = SettingsBackup.snapshot(domain: ["showCPU": true], wakaToken: "new", launchAtLogin: true)
        enum Failure: Error { case denied }
        var login = false
        var tokenWritten = false
        XCTAssertThrowsError(try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name,
            readToken: { "old" }, readLaunch: { login },
            writeLaunch: { value in login = value; if value { throw Failure.denied } },
            writeToken: { _ in tokenWritten = true })) { error in
                guard case SettingsBackup.BackupError.launchRestoreFailed = error else { return XCTFail("Expected login failure") }
            }
        XCTAssertFalse(login)
        XCTAssertFalse(tokenWritten)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["showCPU"] as? Bool, false)
    }

    func testCredentialFailureRollsBackLogin() {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["showCPU": false], forName: name)
        let snapshot = SettingsBackup.snapshot(domain: ["showCPU": true], wakaToken: "new", launchAtLogin: true)
        enum Failure: Error { case denied }
        var login = false
        var token = "old"
        XCTAssertThrowsError(try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name,
            readToken: { token }, readLaunch: { login }, writeLaunch: { login = $0 },
            writeToken: { value in
                token = value ?? ""
                if value == "new" { throw Failure.denied }
            }))
        XCTAssertFalse(login)
        XCTAssertEqual(token, "old")
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["showCPU"] as? Bool, false)
    }

    func testUnavailableLoginAndRollbackFailure() {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.setPersistentDomain(["showCPU": false], forName: name)
        let snapshot = SettingsBackup.snapshot(domain: ["showCPU": true], wakaToken: nil, launchAtLogin: true)
        enum Failure: Error { case denied }
        var writes = 0
        XCTAssertThrowsError(try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name,
            readToken: { nil }, readLaunch: { throw Failure.denied },
            writeLaunch: { _ in writes += 1 }, writeToken: { _ in writes += 1 }))
        XCTAssertEqual(writes, 0)
        XCTAssertThrowsError(try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name,
            readToken: { nil }, readLaunch: { false },
            writeLaunch: { _ in throw Failure.denied }, writeToken: { _ in writes += 1 })) { error in
                guard case SettingsBackup.BackupError.rollbackFailed = error else { return XCTFail("Expected rollback failure") }
            }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["showCPU"] as? Bool, false)
    }

    func testFileReadIsBounded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let limit = 4 * 1024 * 1024 + 52
        try Data(repeating: 1, count: limit).write(to: url)
        XCTAssertEqual(try SettingsBackup.readFile(at: url).count, limit)
        try Data(repeating: 1, count: limit + 1).write(to: url)
        XCTAssertThrowsError(try SettingsBackup.readFile(at: url))
    }

    func testMissingTokenRestoresTombstone() throws {
        let name = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = SettingsBackup.snapshot(domain: [:], wakaToken: nil, launchAtLogin: false)
        var invoked = false
        try SettingsBackup.restore(snapshot, defaults: defaults, domainName: name, readToken: { "old" }, readLaunch: { false }, writeLaunch: { _ in }) { token in
            invoked = true
            XCTAssertNil(token)
        }
        XCTAssertTrue(invoked)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?[WakaTimeCredentialHint.defaultsKey] as? String, "notConfigured")
    }
}
