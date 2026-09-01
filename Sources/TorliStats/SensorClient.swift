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
                    diagnosticMessage: values["diagnosticMessage"] as? String,
                    fanReason: values["fanReason"] as? String ?? "未返回风扇诊断信息。",
                    cpuTemperatureReason: values["cpuTemperatureReason"] as? String ?? "未返回 CPU 温度诊断信息。",
                    gpuTemperatureReason: values["gpuTemperatureReason"] as? String ?? "未返回 GPU 温度诊断信息。"
                )
                finish(sensorValues)
            }
        }
    }

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
        diagnosticMessage: "无法连接传感器辅助进程；请确认已授权安装并正在运行。",
        fanReason: "无法连接传感器辅助进程。",
        cpuTemperatureReason: "无法连接传感器辅助进程。",
        gpuTemperatureReason: "无法连接传感器辅助进程。"
    )
}
