import CryptoKit
import Foundation
import XCTest
@testable import TorliStats

final class UpdateInstallerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testCommandTimeoutTerminatesItsChildProcessGroup() throws {
        let marker = directory.appendingPathComponent("late-write")
        XCTAssertThrowsError(try executeUpdateCommand(
            "/bin/bash",
            ["-c", "(/bin/sleep 2; /usr/bin/touch \"$1\") & wait", "test-child", marker.path],
            timeout: 0.2
        ))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCommandOutputIsCaptured() throws {
        let output = try executeUpdateCommand("/usr/bin/printf", ["hello"], timeout: 5, capture: true)
        XCTAssertEqual(String(data: output, encoding: .utf8), "hello")
    }

    func testReleaseMustBeAnExactTrustedSemanticVersionTag() throws {
        func release(_ version: String, _ url: String) -> AppUpdateRelease {
            AppUpdateRelease(version: version, downloadURL: URL(string: url)!, publishedAt: nil)
        }
        let root = "https://github.com/JamesLi-dev/torli-stats/releases/tag/"
        XCTAssertEqual(try validatedVersion(release("1.2.3", root + "v1.2.3")), "1.2.3")
        XCTAssertThrowsError(try validatedVersion(release("1.2", root + "v1.2")))
        XCTAssertThrowsError(try validatedVersion(release("01.2.3", root + "v01.2.3")))
        XCTAssertThrowsError(try validatedVersion(release("1.2.3", root + "v1.2.4")))
        XCTAssertThrowsError(try validatedVersion(release("1.2.3", "https://github.com.evil.example/JamesLi-dev/torli-stats/releases/tag/v1.2.3")))
        XCTAssertThrowsError(try validatedVersion(release("1.2.3", "http://github.com/JamesLi-dev/torli-stats/releases/tag/v1.2.3")))
        XCTAssertThrowsError(try validatedVersion(release("1.2.3", root + "v1.2.3?other=1")))
    }

    func testChecksumRequiresOneMatchingArchiveAndCorrectDigest() throws {
        let archive = Data("archive".utf8)
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        let line = "\(digest)  TorliStats-1.2.3-macos-arm64.zip\n"
        XCTAssertNoThrow(try verifyChecksum(sums: Data(line.utf8), archive: archive, name: "TorliStats-1.2.3-macos-arm64.zip"))
        XCTAssertThrowsError(try verifyChecksum(sums: Data((line + line).utf8), archive: archive, name: "TorliStats-1.2.3-macos-arm64.zip"))
        XCTAssertThrowsError(try verifyChecksum(sums: Data(line.utf8), archive: Data("different".utf8), name: "TorliStats-1.2.3-macos-arm64.zip"))
        XCTAssertThrowsError(try verifyChecksum(sums: Data(line.utf8), archive: archive, name: "another.zip"))
    }

    func testZipRejectsTraversalLinksDuplicatesAndOversize() throws {
        XCTAssertNoThrow(try validateArchive(zip([Entry("TorliStats.app/Contents/Info.plist")])))
        XCTAssertThrowsError(try validateArchive(zip([Entry("TorliStats.app/../../escape")])))
        XCTAssertThrowsError(try validateArchive(zip([Entry("TorliStats.app/link", mode: 0o120777)])))
        XCTAssertThrowsError(try validateArchive(zip([Entry("TorliStats.app/a"), Entry("TorliStats.app/A")])))
        XCTAssertThrowsError(try validateArchive(zip([Entry("TorliStats.app/big", expanded: 300 * 1024 * 1024)])))
        XCTAssertThrowsError(try validateArchive(zip([Entry("/TorliStats.app/evil")])))
        XCTAssertThrowsError(try validateArchive(zip([Entry("TorliStats.app/Contents\\evil")])))
    }

    func testZipRejectsMismatchedLocalNameAndTruncation() throws {
        var data = zip([Entry("TorliStats.app/file")])
        data[30] = 0x58
        XCTAssertThrowsError(try validateArchive(data))
        XCTAssertThrowsError(try validateArchive(Data(data.dropLast())))
    }

    func testSwapSucceedsAndRollbackRestoresOriginal() throws {
        let target = directory.appendingPathComponent("installed.app")
        let replacement = directory.appendingPathComponent("staged.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
        try Data("old".utf8).write(to: target.appendingPathComponent("version"))
        try Data("new".utf8).write(to: replacement.appendingPathComponent("version"))
        struct LaunchFailure: Error {}
        XCTAssertThrowsError(try swapAndLaunch(target: target, replacement: replacement) { throw LaunchFailure() })
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: replacement.appendingPathComponent("version"), encoding: .utf8), "new")
        try swapAndLaunch(target: target, replacement: replacement) {}
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: replacement.appendingPathComponent("version"), encoding: .utf8), "old")
    }

    func testHomebrewRecoveryRestoresOldAppWithoutTouchingPro() throws {
        let target = directory.appendingPathComponent("installed.app")
        let backup = directory.appendingPathComponent("backup.app")
        func makeApp(_ url: URL, version: String, executable: String = "TorliStats") throws {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": "local.torli.stats", "CFBundleExecutable": executable, "CFBundleShortVersionString": version]
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"))
        }
        func version(_ url: URL) throws -> String {
            let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            return try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        }
        try makeApp(backup, version: "1.0.0")
        try makeApp(target, version: "2.0.0")
        XCTAssertTrue(try recoverHomebrewApp(target: target, backup: backup, newVersion: "2.0.0", oldVersion: "1.0.0"))
        XCTAssertEqual(try version(target), "1.0.0")
        XCTAssertEqual(try version(backup), "1.0.0")
        try FileManager.default.removeItem(at: target)
        XCTAssertTrue(try recoverHomebrewApp(target: target, backup: backup, newVersion: "2.0.0", oldVersion: "1.0.0"))
        XCTAssertEqual(try version(target), "1.0.0")
        try FileManager.default.removeItem(at: target)
        try makeApp(target, version: "2.0.0", executable: "TorliStatsPro")
        XCTAssertThrowsError(try recoverHomebrewApp(target: target, backup: backup, newVersion: "2.0.0", oldVersion: "1.0.0"))
        XCTAssertEqual(try version(target), "2.0.0")
        XCTAssertEqual(try version(backup), "1.0.0")
    }

    func testHomebrewRecoveryAllowsSymlinkedParentButNotSymlinkedApp() throws {
        let realParent = directory.appendingPathComponent("real", isDirectory: true)
        let aliasParent = directory.appendingPathComponent("alias", isDirectory: true)
        let backup = directory.appendingPathComponent("backup.app")
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: realParent)
        func makeApp(_ url: URL, version: String) throws {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": "local.torli.stats", "CFBundleExecutable": "TorliStats", "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        let realTarget = realParent.appendingPathComponent("installed.app")
        let targetThroughAlias = aliasParent.appendingPathComponent("installed.app")
        try makeApp(backup, version: "1.0.0")
        try makeApp(realTarget, version: "2.0.0")
        XCTAssertTrue(try recoverHomebrewApp(target: targetThroughAlias, backup: backup, newVersion: "2.0.0", oldVersion: "1.0.0"))
        let restored = try Data(contentsOf: realTarget.appendingPathComponent("Contents/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: restored, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        try FileManager.default.removeItem(at: realTarget)
        try FileManager.default.createSymbolicLink(at: realTarget, withDestinationURL: backup)
        XCTAssertFalse(try recoverHomebrewApp(target: targetThroughAlias, backup: backup, newVersion: "2.0.0", oldVersion: "1.0.0"))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: realTarget.path), backup.path)
    }

    private struct Entry {
        let name: String
        let mode: UInt32
        let expanded: UInt32
        init(_ name: String, mode: UInt32 = 0o100644, expanded: UInt32 = 0) {
            self.name = name
            self.mode = mode
            self.expanded = expanded
        }
    }

    // Minimal stored ZIP records let each adversarial header be exercised
    // without invoking an archive tool or writing outside the test directory.
    private func zip(_ entries: [Entry]) -> Data {
        var result = Data()
        var central = Data()
        func word(_ value: UInt16, into data: inout Data) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func dword(_ value: UInt32, into data: inout Data) {
            word(UInt16(truncatingIfNeeded: value), into: &data)
            word(UInt16(truncatingIfNeeded: value >> 16), into: &data)
        }
        for entry in entries {
            let name = Data(entry.name.utf8)
            let offset = UInt32(result.count)
            dword(0x04034b50, into: &result)
            word(20, into: &result); word(0, into: &result); word(0, into: &result)
            word(0, into: &result); word(0, into: &result); dword(0, into: &result)
            dword(0, into: &result); dword(entry.expanded, into: &result)
            word(UInt16(name.count), into: &result); word(0, into: &result); result.append(name)
            dword(0x02014b50, into: &central)
            word(0x0314, into: &central); word(20, into: &central)
            word(0, into: &central); word(0, into: &central); word(0, into: &central); word(0, into: &central)
            dword(0, into: &central); dword(0, into: &central); dword(entry.expanded, into: &central)
            word(UInt16(name.count), into: &central); word(0, into: &central); word(0, into: &central)
            word(0, into: &central); word(0, into: &central); dword(entry.mode << 16, into: &central)
            dword(offset, into: &central); central.append(name)
        }
        let start = UInt32(result.count)
        result.append(central)
        dword(0x06054b50, into: &result)
        word(0, into: &result); word(0, into: &result)
        word(UInt16(entries.count), into: &result); word(UInt16(entries.count), into: &result)
        dword(UInt32(central.count), into: &result); dword(start, into: &result); word(0, into: &result)
        return result
    }
}
