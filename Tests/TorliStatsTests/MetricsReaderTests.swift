import XCTest
import Observation
import IOKit.ps
@testable import TorliStats

final class MetricsReaderTests: XCTestCase {
    func testNetworkDeltaCrossesFourGiBWithoutWrapping() {
        let boundary: UInt64 = 1 << 32
        let old = NetworkTotals(interfaces: ["en0": .init(received: boundary - 10, sent: boundary + 50)])
        let next = NetworkTotals(interfaces: ["en0": .init(received: boundary + 90, sent: boundary + 250)])
        XCTAssertEqual(next.delta(since: old).received, 100)
        XCTAssertEqual(next.delta(since: old).sent, 200)
    }

    func testInterfaceResetOrAdditionDoesNotBecomeTrafficSpike() {
        let old = NetworkTotals(interfaces: ["en0": .init(received: 1000, sent: 1000), "en1": .init(received: 100, sent: 100)])
        let next = NetworkTotals(interfaces: ["en0": .init(received: 10, sent: 10), "en1": .init(received: 120, sent: 140), "en2": .init(received: 999999, sent: 999999)])
        XCTAssertEqual(next.delta(since: old).received, 20)
        XCTAssertEqual(next.delta(since: old).sent, 40)
        XCTAssertNil(NetworkReader.parse(Data([0, 0, 0, 0])))
        XCTAssertNil(NetworkReader.parse(Data([255, 255, 0, 18])))
        XCTAssertNil(NetworkReader.parse(Data([1])))
    }

    func testGPURegistryUsesRendererAndFallsBackToDeviceUtilization() {
        XCTAssertEqual(GPUReader.utilization([
            ["PerformanceStatistics": ["Renderer Utilization %": 40, "Device Utilization %": 90]],
            ["PerformanceStatistics": ["Device Utilization %": 20]],
            ["other": 100]
        ]), 40)
        XCTAssertEqual(GPUReader.utilization([["PerformanceStatistics": ["Device Utilization %": 20]]]), 20)
        XCTAssertEqual(GPUReader.utilization([]), 0)
    }

    func testPluggedInButFullBatteryIsNotCharging() {
        let full = BatteryReader.powerState([kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false])
        XCTAssertTrue(full.externalPower)
        XCTAssertFalse(full.charging)
        let charging = BatteryReader.powerState([kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true])
        XCTAssertTrue(charging.externalPower)
        XCTAssertTrue(charging.charging)
        XCTAssertFalse(BatteryReader.powerState([kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue]).externalPower)
    }

    func testCollectorHandlesOutputFailureAndSizeLimit() {
        XCTAssertEqual(BoundedProcess.output("/bin/echo", arguments: ["hello"]), Data("hello\n".utf8))
        XCTAssertNil(BoundedProcess.output("/usr/bin/false", arguments: []))
        XCTAssertNil(BoundedProcess.output("/usr/bin/yes", arguments: [], maximumBytes: 1024))
    }

    func testBatteryHealthSupportsFlatAndNestedRegistryCounters() {
        let capacities: [String: Any] = ["DesignCapacity": 5000, "NominalChargeCapacity": 4500]
        XCTAssertEqual(BatteryReader.registryHealth(capacities), 90)
        XCTAssertEqual(BatteryReader.registryHealth(["BatteryData": capacities]), 90)
        XCTAssertEqual(BatteryReader.registryHealth(["MaximumCapacityPercent": 88, "BatteryData": capacities]), 88)
        XCTAssertNil(BatteryReader.registryHealth(["DesignCapacity": 0, "NominalChargeCapacity": 4500]))
    }

    func testCollectorTimeoutKillsProcessIgnoringTermination() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let start = Date()
        // The temporary path is an argument, never interpolated into shell source.
        XCTAssertNil(BoundedProcess.output("/bin/sh", arguments: ["-c", "trap '' TERM; echo $$ > \"$1\"; while :; do :; done", "test", pidFile.path], timeout: 0.15))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<100 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    @MainActor
    func testObservationTracksOnlyReadMetric() async throws {
        let store = MetricsStore(startsMonitoring: false)
        let cpuChanged = expectation(description: "CPU unchanged")
        cpuChanged.isInverted = true
        let pauseChanged = expectation(description: "Pause changed")
        withObservationTracking { _ = store.cpu } onChange: { cpuChanged.fulfill() }
        withObservationTracking { _ = store.isMonitoringPaused } onChange: { pauseChanged.fulfill() }
        store.setMonitoringPauseState(true, message: "paused")
        await fulfillment(of: [pauseChanged, cpuChanged], timeout: 0.1)
        XCTAssertTrue(store.isMonitoringPaused)
    }
}
