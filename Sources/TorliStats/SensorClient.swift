import Foundation
import TorliStatsShared

struct PrivilegedSensorValues {
    let isHelperReachable: Bool
    let isAvailable: Bool
    let fanRPM: Int?
    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let helperVersion: String?
    let protocolVersion: Int?
    let diagnosticMessage: String?
    let fanReason: String
    let cpuTemperatureReason: String
    let gpuTemperatureReason: String
}

/// Serializes XPC sensor reads off the main thread. The helper can block while
/// opening SMC, so neither its timeout nor its reply handling touches AppKit.
final class SensorClient {
    private var connection: NSXPCConnection?
    private var isReading = false
    private var readID: UInt64 = 0
    private let callbackQueue = DispatchQueue(label: "local.torli.stats.sensor-client", qos: .utility)

    func read(completion: @escaping (PrivilegedSensorValues) -> Void) {
        callbackQueue.async { [weak self] in
            self?.startRead(completion: completion)
        }
    }

    private func startRead(completion: @escaping (PrivilegedSensorValues) -> Void) {
        guard !isReading else { return }
        isReading = true
        readID &+= 1
        let currentReadID = readID

        let finish: (PrivilegedSensorValues) -> Void = { [weak self] values in
            guard let self, self.readID == currentReadID, self.isReading else { return }
            self.isReading = false
            completion(values)
        }

        // A blocked SMC/XPC request must not prevent later reads forever.
        callbackQueue.asyncAfter(deadline: .now() + 5) {
            finish(Self.unavailableValues)
        }

        let connection = makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.callbackQueue.async {
                finish(Self.unavailableValues)
            }
        } as? SensorServiceProtocol

        guard let proxy else {
            finish(Self.unavailableValues)
            return
        }

        proxy.readSensors { [weak self] values in
            guard let self else { return }
            self.callbackQueue.async {
                let sensorValues = PrivilegedSensorValues(
                    isHelperReachable: true,
                    isAvailable: (values["available"] as? NSNumber)?.boolValue ?? false,
                    fanRPM: (values["fanRPM"] as? NSNumber)?.intValue,
                    cpuTemperature: (values["cpuTemperature"] as? NSNumber)?.doubleValue,
                    gpuTemperature: (values["gpuTemperature"] as? NSNumber)?.doubleValue,
                    helperVersion: values["helperVersion"] as? String,
                    protocolVersion: (values["protocolVersion"] as? NSNumber)?.intValue,
                    diagnosticMessage: Self.localizedMessage(
                        values["diagnosticMessage"] as? String,
                        fallbackKey: "sensor.client.no_diagnostic",
                        argument: (values["diagnosticStatus"] as? NSNumber)?.intValue
                    ),
                    fanReason: Self.localizedMessage(values["fanReason"] as? String, fallbackKey: "sensor.client.no_fan_diagnostic"),
                    cpuTemperatureReason: Self.localizedMessage(values["cpuTemperatureReason"] as? String, fallbackKey: "sensor.client.no_cpu_temperature_diagnostic"),
                    gpuTemperatureReason: Self.localizedMessage(values["gpuTemperatureReason"] as? String, fallbackKey: "sensor.client.no_gpu_temperature_diagnostic")
                )
                finish(sensorValues)
            }
        }
    }

    private static func localizedMessage(_ key: String?, fallbackKey: String, argument: Int? = nil) -> String {
        guard let key else { return StatsL10n.text(fallbackKey) }
        let resolvedKey = legacySensorMessageKeys[key] ?? key
        if resolvedKey == "sensor.smc.open_failed_iokit", let argument {
            return StatsL10n.format(resolvedKey, argument)
        }
        return resolvedKey.hasPrefix("sensor.") ? StatsL10n.text(resolvedKey) : resolvedKey
    }

    // Helpers installed by pre-localization versions returned display text rather
    // than a stable message key. Keep those helpers readable in either app
    // language until users reinstall them.
    private static let legacySensorMessageKeys: [String: String] = [
        "已读取风扇转速。": "sensor.fan.read",
        "已读取 CPU 温度。": "sensor.cpu_temperature.read",
        "已读取 GPU 温度。": "sensor.gpu_temperature.read",
        "未发现可读取的风扇转速。": "sensor.fan.unavailable",
        "未返回 CPU 温度诊断信息。": "sensor.client.no_cpu_temperature_diagnostic",
        "未返回 GPU 温度诊断信息。": "sensor.client.no_gpu_temperature_diagnostic",
        "SMC 传感器当前不可用。": "sensor.smc.unavailable"
    ]

    private func makeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(
            machServiceName: SensorServiceConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: SensorServiceProtocol.self)
        connection.invalidationHandler = { [weak self] in
            self?.callbackQueue.async { [weak self] in self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            self?.callbackQueue.async { [weak self] in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private static let unavailableValues = PrivilegedSensorValues(
        isHelperReachable: false,
        isAvailable: false,
        fanRPM: nil,
        cpuTemperature: nil,
        gpuTemperature: nil,
        helperVersion: nil,
        protocolVersion: nil,
        diagnosticMessage: StatsL10n.text("sensor.client.connection_unavailable"),
        fanReason: StatsL10n.text("sensor.client.connection_unavailable_short"),
        cpuTemperatureReason: StatsL10n.text("sensor.client.connection_unavailable_short"),
        gpuTemperatureReason: StatsL10n.text("sensor.client.connection_unavailable_short")
    )
}
