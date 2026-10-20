import Foundation

public enum SensorServiceConstants {
    public static let machServiceName = "local.torli.stats.sensor"
    public static let daemonPlistName = "TorliStatsHelper.plist"
    public static let installedHelperPath = "/Library/PrivilegedHelperTools/TorliStatsHelper"
    public static let protocolVersion = 4
    public static let helperVersion = "1.3"
}

public enum FanControlMode: Int, CaseIterable, Sendable {
    /// Lets macOS own thermal management.
    case automatic = 0
    /// A useful audible cooling step without locking the fans at their limit.
    case cooling = 60
    /// Maximum fan speed for short, deliberate cooling periods.
    case maximumCooling = 100

    public var percentage: Double? {
        self == .automatic ? nil : Double(rawValue) / 100
    }

    public func targetRPM(minimum: Double, maximum: Double) -> Double? {
        guard let percentage, minimum >= 0, maximum >= minimum else { return nil }
        return minimum + (maximum - minimum) * percentage
    }
}

@objc public protocol SensorServiceProtocol {
    func readSensors(withReply reply: @escaping (NSDictionary) -> Void)
    func setFanControlMode(_ mode: NSNumber, withReply reply: @escaping (NSDictionary) -> Void)
}
