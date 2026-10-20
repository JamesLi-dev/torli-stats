import Foundation

public enum SensorServiceConstants {
    public static let machServiceName = "local.torli.stats.sensor"
    public static let daemonPlistName = "TorliStatsHelper.plist"
    public static let installedHelperPath = "/Library/PrivilegedHelperTools/TorliStatsHelper"
    public static let protocolVersion = 5
    public static let helperVersion = "1.4"
}

public enum FanControlMode: Int, CaseIterable, Sendable {
    /// Lets macOS own thermal management.
    case automatic = 0
    /// The user-visible cooling strategy's baseline: 40% of maximum RPM.
    case cooling = 40
    /// Internal cooling-strategy step for elevated heat or CPU load.
    case coolingWarm = 60
    /// Internal cooling-strategy step for high heat or CPU load.
    case coolingHot = 80
    /// Maximum fan speed for short, deliberate cooling periods.
    case maximumCooling = 100

    public var percentage: Double? {
        self == .automatic ? nil : Double(rawValue) / 100
    }

    public var isCoolingStrategyStep: Bool {
        switch self {
        case .cooling, .coolingWarm, .coolingHot:
            return true
        case .automatic, .maximumCooling:
            return false
        }
    }

    /// A conservative, temperature-first cooling curve. CPU usage provides a
    /// small anticipatory boost when temperatures have not caught up yet.
    public static func coolingTarget(maximumTemperature: Double?, cpuUsage: Double) -> Self {
        let temperature = maximumTemperature ?? 0
        if temperature >= 85 || cpuUsage >= 95 { return .maximumCooling }
        if temperature >= 75 || cpuUsage >= 85 { return .coolingHot }
        if temperature >= 65 || cpuUsage >= 65 { return .coolingWarm }
        return .cooling
    }

    public func targetRPM(minimum: Double, maximum: Double) -> Double? {
        guard let percentage, minimum >= 0, maximum >= minimum else { return nil }
        // Percentages shown to people mean a percentage of the reported
        // maximum speed, not a percentage through the min...max interval.
        return max(minimum, maximum * percentage)
    }
}

@objc public protocol SensorServiceProtocol {
    func readSensors(withReply reply: @escaping (NSDictionary) -> Void)
    func setFanControlMode(_ mode: NSNumber, withReply reply: @escaping (NSDictionary) -> Void)
}
