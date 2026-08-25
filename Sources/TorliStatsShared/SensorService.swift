import Foundation

public enum SensorServiceConstants {
    public static let machServiceName = "local.torli.stats.sensor"
    public static let daemonPlistName = "TorliStatsHelper.plist"
}

@objc public protocol SensorServiceProtocol {
    func readSensors(withReply reply: @escaping (NSDictionary) -> Void)
}
