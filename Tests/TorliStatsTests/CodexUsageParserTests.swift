import XCTest
@testable import TorliStats

final class CodexUsageParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAppServerNestedAndFlatLimits() throws {
        let limits: [String: Any] = ["primary": ["usedPercent": "25.5", "windowDurationMins": 300, "resetsAt": 1_800_001_000],
                                   "secondary": ["usedPercent": 30], "credits": ["hasCredits": true, "balance": 12.5], "planType": "plus"]
        for response in [limits, ["rateLimits": limits]] {
            let result = try CodexUsageParser.makeSnapshot(account: ["account": ["email": "alice@example.test"]], rateLimits: response, fetchedAt: now)
            XCTAssertEqual(result.primary?.usedPercent, 25.5)
            XCTAssertEqual(result.primary?.windowDurationMinutes, 300)
            XCTAssertEqual(result.secondary?.usedPercent, 30)
            XCTAssertEqual(result.account.displayPrefix, "ALI")
            XCTAssertEqual(result.account.planType, "plus")
            XCTAssertEqual(result.credits?.balance, "12.5")
            XCTAssertEqual(result.fetchedAt, now)
        }
        XCTAssertEqual(CodexUsageParser.responseID(from: "3"), 3)
        XCTAssertEqual(CodexUsageParser.responseID(from: 2), 2)
        XCTAssertNil(CodexUsageParser.responseID(from: "notification"))
    }

    func testMalformedNumbersCannotCrashOrPublishInvalidUsage() {
        XCTAssertThrowsError(try CodexUsageParser.makeSnapshot(account: nil, rateLimits: [:]))
        XCTAssertNil(CodexUsageParser.parseWindow(["usedPercent": "nan"]))
        XCTAssertNil(CodexUsageParser.parseWindow(["usedPercent": Double.infinity]))
        XCTAssertEqual(CodexUsageParser.parseWindow(["usedPercent": 150])?.usedPercent, 100)
        let result = CodexUsageParser.parseWindow(["usedPercent": -5, "windowDurationMins": 1e100, "resetsAt": "inf"])
        XCTAssertEqual(result?.usedPercent, 0)
        XCTAssertNil(result?.windowDurationMinutes)
        XCTAssertNil(result?.resetsAt)
    }

    func testUnauthorizedErrorRecognizesWrappedStatusAndMessages() {
        for error: [String: Any] in [["code": 401], ["code": -32000, "data": ["status_code": "403"]],
                                    ["message": "Not logged in"], ["message": "Your token has expired"]] {
            XCTAssertTrue(CodexUsageParser.isUnauthorized(error))
        }
        XCTAssertFalse(CodexUsageParser.isUnauthorized(["code": -32601, "message": "Method not found"]))
        XCTAssertFalse(CodexUsageParser.isUnauthorized(["message": "connection refused"]))
    }

    func testSessionSnapshotRetainsTimestampAndRejectsStaleOrUnrelatedLimits() {
        let event = sessionEvent(at: now.addingTimeInterval(-10))
        let result = CodexUsageParser.sessionSnapshot(event, identity: nil, now: now, notBefore: now.addingTimeInterval(-20))
        XCTAssertEqual(result?.fetchedAt, now.addingTimeInterval(-10))
        XCTAssertEqual(result?.account.planType, "plus")
        XCTAssertNil(CodexUsageParser.sessionSnapshot(event, identity: nil, now: now.addingTimeInterval(301), notBefore: .distantPast))
        XCTAssertNil(CodexUsageParser.sessionSnapshot(event, identity: nil, now: now, notBefore: now))
        XCTAssertNil(CodexUsageParser.sessionSnapshot(sessionEvent(at: now, reset: now), identity: nil, now: now, notBefore: .distantPast))
        XCTAssertNil(CodexUsageParser.sessionSnapshot(sessionEvent(at: now, limitID: "other-model"), identity: nil, now: now, notBefore: .distantPast))
    }

    func testLocalReaderUsesOnlyCurrentHomesFreshCompleteRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions/2025/01/01")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let auth = root.appendingPathComponent("auth.json")
        try Data("{\"tokens\":{\"account_id\":\"test\"}}".utf8).write(to: auth)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-30)], ofItemAtPath: auth.path)
        let log = sessions.appendingPathComponent("test.jsonl")
        var data = try JSONSerialization.data(withJSONObject: sessionEvent(at: now.addingTimeInterval(-10)))
        data.append(10)
        data.append(Data("{\"payload\":{\"rate_limits\":".utf8))
        try data.write(to: log)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: log.path)
        XCTAssertEqual(CodexLocalUsageReader.snapshot(home: root, now: now)?.primary?.usedPercent, 20)
        XCTAssertNil(CodexLocalUsageReader.snapshot(home: root.appendingPathComponent("other-account"), now: now))
        XCTAssertNil(CodexLocalUsageReader.snapshot(home: root, now: now.addingTimeInterval(400)))
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: auth.path)
        XCTAssertNil(CodexLocalUsageReader.snapshot(home: root, now: now))
    }

    private func sessionEvent(at timestamp: Date, reset: Date? = nil, limitID: String = "codex") -> [String: Any] {
        ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: timestamp),
         "payload": ["type": "token_count", "rate_limits": ["limit_id": limitID, "plan_type": "plus",
                     "primary": ["used_percent": 20, "window_minutes": 300, "resets_at": (reset ?? now.addingTimeInterval(1000)).timeIntervalSince1970]]]]
    }
}
