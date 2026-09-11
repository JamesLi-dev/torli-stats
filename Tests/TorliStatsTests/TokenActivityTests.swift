import XCTest
@testable import TorliStats

final class TokenActivityTests: XCTestCase {
    func testRecentHistoryReplacesCorrectedDaysWithoutLosingOlderHistory() {
        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11))!
        let start = calendar.date(byAdding: .day, value: -2, to: end)!
        let base = WakaTimePeriod(totalSeconds: 60, activeDayCount: 3, dailyRecords: [
            WakaTimeDailyRecord(dateID: "2026-09-08", totalSeconds: 10, aiTokens: 100),
            WakaTimeDailyRecord(dateID: "2026-09-09", totalSeconds: 20, aiTokens: 200),
            WakaTimeDailyRecord(dateID: "2026-09-10", totalSeconds: 30, aiTokens: 300)
        ])
        let recent = WakaTimePeriod(totalSeconds: 50, activeDayCount: 1, dailyRecords: [
            WakaTimeDailyRecord(dateID: "2026-09-09", totalSeconds: 50, aiTokens: 500)
        ])
        let merged = WakaTimeUsageStore.mergingRecentHistory(base, recent: recent, start: start, end: end)
        XCTAssertEqual(merged.dailyRecords.map(\.dateID), ["2026-09-08", "2026-09-09"])
        XCTAssertEqual(merged.totalSeconds, 60)
        XCTAssertEqual(merged.activeDayCount, 2)
        XCTAssertEqual(merged.dailyRecords.last?.aiTokens, 500)
    }

    @MainActor
    func testAccountsRemainSeparateWhileArchivesDeduplicateAndDiskPathsAreHashed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let homes = [root.appendingPathComponent("account-a"), root.appendingPathComponent("account-b")]
        let cache = root.appendingPathComponent("cache")
        for home in homes {
            for folder in ["sessions", "archived_sessions"] {
                let directory = home.appendingPathComponent(folder)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data((event(100, at: "2026-09-10T01:00:00Z") + "\n").utf8)
                    .write(to: directory.appendingPathComponent("private-session.jsonl"))
            }
        }
        let service = CodexTokenActivityService(homePaths: { homes.map(\.path) }, cacheDirectory: cache)
        service.setEnabled(true)
        for _ in 0..<200 where service.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        service.setEnabled(false)
        XCTAssertFalse(service.isLoading)
        XCTAssertEqual(service.records.map(\.value), [200])
        for file in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains(root.path))
            XCTAssertFalse(contents.contains("private-session"))
            XCTAssertFalse(contents.contains("account-a"))
        }
        // Missing source directories exercise the cached fallback after a restart.
        for home in homes { try FileManager.default.removeItem(at: home) }
        let restarted = CodexTokenActivityService(homePaths: { homes.map(\.path) }, cacheDirectory: cache)
        XCTAssertEqual(restarted.records.map(\.value), [200])
        restarted.setEnabled(true)
        for _ in 0..<200 where restarted.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
        restarted.setEnabled(false)
        XCTAssertFalse(restarted.isLoading)
        XCTAssertEqual(restarted.records.map(\.value), [200])
    }

    func testCachePruningKeepsCurrentAndTwoRecentScopes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let scopes = (0..<5).map { "v2-" + String(repeating: String($0), count: 64) }
        let legacy = String(repeating: "a", count: 64)
        for (index, scope) in (scopes + [legacy]).enumerated() {
            for kind in ["index", "summary"] {
                let file = root.appendingPathComponent("\(scope)-\(kind).json")
                try Data("{}".utf8).write(to: file)
                let age = index == 0 || index == 4 ? 40 : index
                try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-Double(age) * 86400)], ofItemAtPath: file.path)
            }
        }
        let unrelated = root.appendingPathComponent("keep.txt")
        try Data().write(to: unrelated)
        try CodexTokenActivityService.pruneCache(at: root, currentScope: scopes[0], now: now)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names.count, 7)
        for scope in scopes.prefix(3) {
            XCTAssertTrue(names.contains("\(scope)-index.json"))
            XCTAssertTrue(names.contains("\(scope)-summary.json"))
        }
        XCTAssertTrue(names.contains("keep.txt"))
    }

    func testIncrementalReadResumesPartialLineAfterCacheRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let first = event(100, at: "2026-09-10T01:00:00Z") + "\n"
        let second = event(160, at: "2026-09-11T01:00:00Z") + "\n"
        try Data((first + String(second.prefix(40))).utf8).write(to: file)
        let cached = try CodexTokenActivityService.readIncrement(file, cached: nil)
        XCTAssertEqual(cached.offset, UInt64(first.utf8.count))
        let restored = try JSONDecoder().decode(CodexTokenActivityService.CachedFile.self, from: JSONEncoder().encode(cached))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(second.dropFirst(40).utf8))
        try handle.close()
        let updated = try CodexTokenActivityService.readIncrement(file, cached: restored)
        XCTAssertEqual(updated.events.map(\.tokens), [100, 60])
        XCTAssertEqual(updated.offset, UInt64((first + second).utf8.count))
    }

    func testTruncatedFileRebuildsInsteadOfAddingOldUsage() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data((event(1000, at: "2026-09-10T01:00:00Z") + "\n").utf8).write(to: file)
        let cached = try CodexTokenActivityService.readIncrement(file, cached: nil)
        try Data((event(10, at: "2026-09-10T01:00:00Z") + "\n").utf8).write(to: file)
        let updated = try CodexTokenActivityService.readIncrement(file, cached: cached)
        XCTAssertEqual(updated.events.map(\.tokens), [10])
    }

    @MainActor
    func testRestartImmediatelyRestoresSummaryWithoutScanning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data((event(100, at: "2026-09-10T01:00:00Z") + "\n").utf8)
            .write(to: sessions.appendingPathComponent("test.jsonl"))
        let service = CodexTokenActivityService(homePaths: { [root.path] }, cacheDirectory: cache)
        service.setEnabled(true)
        for _ in 0..<200 where service.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(service.isLoading)
        service.setEnabled(false)
        let restarted = CodexTokenActivityService(homePaths: { [root.path] }, cacheDirectory: cache)
        XCTAssertEqual(restarted.records.map(\.value), [100])
        XCTAssertFalse(restarted.isLoading)
        let otherHome = CodexTokenActivityService(homePaths: { [root.appendingPathComponent("other").path] }, cacheDirectory: cache)
        XCTAssertTrue(otherHome.records.isEmpty)
    }

    private func event(_ total: Int, at timestamp: String) -> String {
        """
        {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total),"cached_input_tokens":50}}}}
        """
    }

    private func read(_ lines: String) throws -> [CodexTokenActivityService.TokenEvent] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try Data(lines.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return try CodexTokenActivityService.read(file)
    }

    func testCumulativeEventsCountOnlyNewTokensAndIgnoreRepeatedSnapshots() throws {
        let records = try read([
            event(100, at: "2026-09-10T01:00:00.000Z"),
            event(100, at: "2026-09-10T01:00:01.000Z"),
            event(160, at: "2026-09-11T01:00:00Z")
        ].joined(separator: "\n") + "\n")
        XCTAssertEqual(records.map(\.tokens), [100, 60])
        XCTAssertEqual(records.reduce(0) { $0 + $1.tokens }, 160)
        XCTAssertNotEqual(records[0].dateID, records[1].dateID)
    }

    func testCounterResetStartsNewDelta() throws {
        let records = try read([
            event(100, at: "2026-09-10T01:00:00Z"),
            event(20, at: "2026-09-10T01:01:00Z"),
            event(30, at: "2026-09-10T01:02:00Z")
        ].joined(separator: "\n") + "\n")
        XCTAssertEqual(records.map(\.tokens), [100, 20, 10])
    }

    func testMalformedAndIncompleteLinesDoNotBecomeUsage() throws {
        let valid = event(10, at: "2026-09-10T01:00:00Z")
        let records = try read("not json\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":null}}\n" + valid + "\n" + event(50, at: "2026-09-10T01:01:00Z"))
        XCTAssertEqual(records.map(\.tokens), [10])
    }

    func testArchivedCopiesHaveSameDeduplicationKey() throws {
        let line = event(100, at: "2026-09-10T01:00:00Z") + "\n"
        XCTAssertEqual(try read(line).first?.key, try read(line).first?.key)
    }
}
