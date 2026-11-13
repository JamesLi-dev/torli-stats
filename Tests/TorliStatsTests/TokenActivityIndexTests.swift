import XCTest
import CryptoKit
@testable import TorliStats

final class TokenActivityIndexTests: XCTestCase {
    func testAppendDeduplicateRebuildRemoveAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("index.sqlite")
        var index: TokenActivityIndex? = try TokenActivityIndex(url: url)
        try index!.transaction {
            try index!.update(key: "a", value: value(home: "home-a", tokens: [100]), replacingEvents: true)
            try index!.update(key: "archive", value: value(home: "home-a", tokens: [100]), replacingEvents: true)
            try index!.update(key: "b", value: value(home: "home-b", tokens: [100]), replacingEvents: true)
        }
        XCTAssertEqual(try index!.records().map(\.value), [200])
        try index!.transaction {
            try index!.update(key: "a", value: value(home: "home-a", tokens: [60]), replacingEvents: false)
        }
        XCTAssertEqual(try index!.records().map(\.value), [260])
        XCTAssertTrue(try index!.metadata().values.allSatisfy { $0.file.events.isEmpty })
        index = nil
        index = try TokenActivityIndex(url: url)
        XCTAssertEqual(try index!.records().map(\.value), [260])
        try index!.transaction {
            try index!.update(key: "a", value: value(home: "home-a", tokens: [10]), replacingEvents: true)
            try index!.remove(keys: ["archive"])
        }
        XCTAssertEqual(try index!.records().map(\.value), [110])
        enum Failure: Error { case intentional }
        XCTAssertThrowsError(try index!.transaction {
            try index!.remove(keys: ["a", "b"])
            throw Failure.intentional
        })
        XCTAssertEqual(try index!.records().map(\.value), [110])
    }

    @MainActor
    func testLegacyMigrationAndServiceAppendPreserveTotals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let log = sessions.appendingPathComponent("test.jsonl")
        let first = "{\"type\":\"event_msg\",\"timestamp\":\"2026-09-10T01:00:00Z\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":100}}}}\n"
        try Data(first.utf8).write(to: log)
        let old = try CodexTokenActivityService.readIncrement(log, cached: nil)
        let scope = "v2-" + digest(root.path + "|" + TimeZone.autoupdatingCurrent.identifier)
        let legacy = cache.appendingPathComponent("\(scope)-index.json")
        try JSONEncoder().encode([digest(log.path): CodexTokenActivityService.ScopedFile(homeScope: digest(root.path), file: old)]).write(to: legacy)
        let service = CodexTokenActivityService(homePaths: { [root.path] }, cacheDirectory: cache)
        service.setEnabled(true)
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [100])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let db = cache.appendingPathComponent("\(scope)-index.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(first.replacingOccurrences(of: "01:00:00", with: "01:01:00").replacingOccurrences(of: "100", with: "160").utf8))
        try handle.close()
        service.refresh()
        try await wait(service)
        XCTAssertEqual(service.records.map(\.value), [160])
        let before = try Data(contentsOf: db)
        service.refresh()
        try await wait(service)
        XCTAssertEqual(try Data(contentsOf: db), before, "An unchanged scan must not rewrite the index")
        service.setEnabled(false)
        let restarted = CodexTokenActivityService(homePaths: { [root.path] }, cacheDirectory: cache)
        restarted.setEnabled(true)
        try await wait(restarted)
        XCTAssertEqual(restarted.records.map(\.value), [160])
        restarted.setEnabled(false)
    }

    private func value(home: String, tokens: [Double]) -> CodexTokenActivityService.ScopedFile {
        .init(homeScope: home, file: .init(modified: Date(timeIntervalSince1970: 1), size: 100,
            created: Date(timeIntervalSince1970: 0), offset: 100, previous: tokens.last ?? 0,
            events: tokens.map { .init(key: "event-\($0)", dateID: "2026-09-10", tokens: $0) }))
    }

    private func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor private func wait(_ service: CodexTokenActivityService) async throws {
        for _ in 0..<200 where service.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(service.isLoading)
    }
}
