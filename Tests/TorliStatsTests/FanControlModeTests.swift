import XCTest
import TorliStatsShared

final class FanControlModeTests: XCTestCase {
    func testTargetRPMUsesPercentageOfMaximumSpeed() {
        XCTAssertEqual(
            FanControlMode.coolingWarm.targetRPM(minimum: 1_511, maximum: 5_776)!,
            3_465.6,
            accuracy: 0.001
        )
    }

    func testTargetRPMNeverFallsBelowHardwareMinimum() {
        XCTAssertEqual(
            FanControlMode.cooling.targetRPM(minimum: 900, maximum: 1_500),
            900
        )
    }

    func testCoolingCurveUsesTemperatureAndCPUUsage() {
        XCTAssertEqual(FanControlMode.coolingTarget(maximumTemperature: 50, cpuUsage: 10), .cooling)
        XCTAssertEqual(FanControlMode.coolingTarget(maximumTemperature: 66, cpuUsage: 10), .coolingWarm)
        XCTAssertEqual(FanControlMode.coolingTarget(maximumTemperature: 76, cpuUsage: 10), .coolingHot)
        XCTAssertEqual(FanControlMode.coolingTarget(maximumTemperature: 86, cpuUsage: 10), .maximumCooling)
        XCTAssertEqual(FanControlMode.coolingTarget(maximumTemperature: nil, cpuUsage: 90), .coolingHot)
    }
}
