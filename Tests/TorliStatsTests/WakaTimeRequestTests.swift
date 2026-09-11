import XCTest
@testable import TorliStats

@MainActor
final class WakaTimeRequestTests: XCTestCase {
    private func snapshot(_ seconds: Double) -> WakaTimeSnapshot {
        WakaTimeSnapshot(totalSeconds: seconds, humanReadableTotal: "test", languages: [], editors: [], categories: [], operatingSystems: [], aiInputTokens: 0, aiCachedInputTokens: 0, aiOutputTokens: 0, aiModelTotalCost: 0, aiModelBreakdown: [])
    }

    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testSnapshotCompletionDrainsPendingRangeAndRejectsPreviousGeneration() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        var key = "a"
        var calls: [(String, WakaTimeRange, (Result<WakaTimeSnapshot, Error>) -> Void)] = []
        let requests = WakaTimeUsageStore.Requests(snapshot: { calls.append(($0, $1, $2)) }, today: { _, _, _ in XCTFail("Unexpected request") }, period: { _, _, _, _ in XCTFail("Unexpected request") })
        let store = WakaTimeUsageStore(apiKeyProvider: { key }, rangeProvider: { .last30Days }, cacheDirectory: cache, requests: requests)
        store.setAutomaticRefreshPaused(true)
        store.synchronize(isEnabled: true)
        store.loadSnapshotIfNeeded(for: .last30Days)
        store.loadSnapshotIfNeeded(for: .last7Days)
        calls[0].2(.success(snapshot(30)))
        await settle()
        XCTAssertEqual(calls.map { $0.1 }, [.last30Days, .last7Days])
        // A -> B -> A must still invalidate the old A response.
        key = "b"
        store.synchronize(isEnabled: true)
        key = "a"
        store.synchronize(isEnabled: true)
        store.loadSnapshotIfNeeded(for: .last7Days)
        XCTAssertEqual(calls.count, 3)
        calls[1].2(.success(snapshot(999)))
        await settle()
        XCTAssertNil(store.snapshots[.last7Days])
        calls[2].2(.success(snapshot(7)))
        await settle()
        XCTAssertEqual(store.snapshots[.last7Days]?.totalSeconds, 7)
    }

    func testDailyCompletionDrainsPendingRangeAndRejectsOldAccount() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        var key = "a"
        var ranges: [WakaTimeRange] = []
        var daily: [(Result<WakaTimeUsageClient.DailyData, Error>) -> Void] = []
        let period = WakaTimePeriod(totalSeconds: 1, activeDayCount: 1, dailyRecords: [])
        let data = WakaTimeUsageClient.DailyData(period: period, snapshot: snapshot(1))
        let value = snapshot(30)
        let requests = WakaTimeUsageStore.Requests(snapshot: { _, range, completion in ranges.append(range); completion(.success(value)) }, today: { _, _, completion in daily.append(completion) }, period: { _, _, _, completion in completion(.success(period)) })
        let store = WakaTimeUsageStore(apiKeyProvider: { key }, rangeProvider: { .last30Days }, cacheDirectory: cache, requests: requests)
        store.synchronize(isEnabled: true)
        daily[0](.success(data))
        await settle()
        store.synchronize(isEnabled: true)
        XCTAssertEqual(daily.count, 2)
        store.loadSnapshotIfNeeded(for: .last7Days)
        daily[1](.success(data))
        await settle()
        await settle()
        XCTAssertTrue(ranges.contains(.last7Days))
        XCTAssertNotNil(store.snapshots[.last7Days])
        store.synchronize(isEnabled: true)
        XCTAssertEqual(daily.count, 3)
        key = "b"
        store.synchronize(isEnabled: true)
        daily[2](.success(data))
        await settle()
        XCTAssertNil(store.todayPeriod)
        daily[3](.success(data))
        await settle()
        XCTAssertEqual(store.todayPeriod?.totalSeconds, 1)
        store.synchronize(isEnabled: false)
    }
}
