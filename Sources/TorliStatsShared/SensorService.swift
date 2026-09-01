import Foundation

public enum SensorServiceConstants {
    public static let machServiceName = "local.torli.stats.sensor"
    public static let daemonPlistName = "TorliStatsHelper.plist"
    public static let installedHelperPath = "/Library/PrivilegedHelperTools/TorliStatsHelper"
    public static let protocolVersion = 1
    public static let helperVersion = "1.0"
}

@objc public protocol SensorServiceProtocol {
    func readSensors(withReply reply: @escaping (NSDictionary) -> Void)
}
