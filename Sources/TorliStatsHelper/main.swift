import Foundation
import IOKit
import TorliStatsShared

final class SensorService: NSObject, SensorServiceProtocol {
    func readSensors(withReply reply: @escaping (NSDictionary) -> Void) {
        reply(SMCReader.snapshot())
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = SensorService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SensorServiceProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = {}
        connection.interruptionHandler = {}
        connection.resume()
        return true
    }
}

private enum SMCReader {
    // SMC key names are not a public API and differ between Apple Silicon
    // generations. We use the known keys as a fallback, but also enumerate
    // the keys exposed by the current machine instead of assuming that an M1
    // key layout is valid on every model.
    private static let fallbackCPUKeys = [
        "Tp01", "Tp02", "Tp04", "Tp05", "Tp06", "Tp08", "Tp09", "Tp0A", "Tp0D", "Tp0P", "Tp0T", "Tp0Y",
        "Tp20", "Tp21", "Tp24", "Tp25", "Tp28", "Tp2A", "Tp2D", "Tp2P", "Tp2Y", "Te00", "Te01",
        "TCMb", "TCMz", "TCDX", "TC0P", "TC0D"
    ]
    private static let fallbackGPUKeys = [
        "Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0K", "Tg0L", "Tg0S", "Tg0T", "Tg0a", "Tg0i", "Tg0j",
        "Tg0q", "Tg0r", "Tg0y", "Tg0z", "Tg4a", "Tg7a", "Tg12", "Tg15", "Tg20", "Tg23", "Tg28",
        "Tg31", "Tg0P", "Tg0f", "TG0P", "TG0D", "TG0T", "TG1D", "TGDD"
    ]
    // Apple Silicon exposes different numbers of cluster sensors on
    // different generations. Keep these known four-character keys as a
    // fallback even when key enumeration is unavailable.
    private static let appleSiliconCPUKeys = (1...16).map { String(format: "Tp%02d", $0) }

    private static let smc = SMCConnection()
    private static var lastFanRPM: Int?
    private static var lastCPUTemperature: Double?
    private static var lastGPUTemperature: Double?

    static func snapshot() -> NSDictionary {
        guard smc.open() else {
            return [
                "available": false,
                "helperVersion": SensorServiceConstants.helperVersion,
                "protocolVersion": SensorServiceConstants.protocolVersion,
                "smcAvailable": false,
                "diagnosticMessage": smc.openFailureDescription ?? "无法打开 AppleSMC 服务。",
                "fanReason": "SMC 服务不可用。",
                "cpuTemperatureReason": "SMC 服务不可用。",
                "gpuTemperatureReason": "SMC 服务不可用。"
            ]
        }

        let discovered = smc.discoverKeys()
        let cpuKeys = unique(fallbackCPUKeys + appleSiliconCPUKeys + discovered.filter {
            $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("TC")
        })
        let gpuKeys = unique(fallbackGPUKeys + discovered.filter { $0.hasPrefix("Tg") || $0.hasPrefix("TG") })
        // Do not depend on discoverKeys() for fans. Some Apple Silicon
        // versions expose the keys through the endpoint but do not return
        // them from the key index query.
        // SMC keys are exactly four characters, so fan indexes are encoded
        // as F0Ac...F9Ac (there is no valid five-character F10Ac key).
        let knownFanKeys = (0...9).map { "F\($0)Ac" }
        let fanKeys = unique(knownFanKeys + discovered.filter {
            $0.count == 4 && $0.first == "F" && $0.hasSuffix("Ac")
        })

        var result: [String: Any] = [
            "available": true,
            "helperVersion": SensorServiceConstants.helperVersion,
            "protocolVersion": SensorServiceConstants.protocolVersion,
            "smcAvailable": true
        ]

        // Zero is a valid reading: a MacBook fan can be stopped. Only an
        // absent/unreadable key should be treated as missing.
        let fanValues = fanKeys.compactMap { smc.readNumber($0) }
            .filter { $0 >= 0 && $0 < 20_000 }
        if let rpm = fanValues.max() {
            lastFanRPM = Int(rpm.rounded())
            result["fanReason"] = "已读取风扇转速。"
        } else {
            result["fanReason"] = "此 Mac 未暴露可读取的风扇转速。"
        }

        // Ignore implausibly low values. Those are usually non-temperature /
        // status keys that happen to use a temperature-looking SMC data type.
        let cpuReadings = cpuKeys.compactMap { key -> (String, Double)? in
            guard let value = smc.readNumber(key), value >= 10, value <= 125 else { return nil }
            return (key, value)
        }
        // TCMz is the CPU-die hotspot and is closest to what monitoring
        // utilities label as "CPU temperature". TCMb is the steadier average
        // fallback. Do not use an arbitrary hottest Tp key as the primary
        // value: some firmware keys are not CPU temperatures despite their T*
        // names and can produce 100+°C-looking outliers.
        let preferredCPUKeys = ["TCMz", "TCMb", "TCDX", "TC0P"]
        if let temperature = preferredCPUKeys.compactMap({ key in
            cpuReadings.first(where: { $0.0 == key })?.1
        }).first {
            lastCPUTemperature = temperature
        } else {
            // A median across all T* keys can be skewed by power-management
            // and package sensors. Tp01...Tp16 are the CPU cluster sensors;
            // the hottest valid cluster is a more useful dashboard value.
            let clusterReadings = cpuReadings.filter { isAppleSiliconCPUKey($0.0) }
            let temperature = clusterReadings.map { $0.1 }.max()
                ?? median(cpuReadings.map { $0.1 })
            if let temperature { lastCPUTemperature = temperature }
        }
        result["cpuTemperatureReason"] = lastCPUTemperature == nil
            ? "未发现可读取的 CPU 温度传感器。"
            : "已读取 CPU 温度。"

        let gpuReadings = gpuKeys.compactMap { key -> (String, Double)? in
            guard let value = smc.readNumber(key), value >= 10, value <= 125 else { return nil }
            return (key, value)
        }
        // GPU keys describe different GPU regions. Use the hottest valid
        // region, matching the thermal hotspot shown by most monitoring
        // utilities rather than a cool-region median.
        if let temperature = gpuReadings.map({ $0.1 }).max() {
            lastGPUTemperature = temperature
        }
        result["gpuTemperatureReason"] = lastGPUTemperature == nil
            ? "未发现可读取的 GPU 温度传感器。"
            : "已读取 GPU 温度。"

        if let lastFanRPM { result["fanRPM"] = NSNumber(value: lastFanRPM) }
        if let lastCPUTemperature { result["cpuTemperature"] = NSNumber(value: lastCPUTemperature) }
        if let lastGPUTemperature { result["gpuTemperature"] = NSNumber(value: lastGPUTemperature) }
        return result as NSDictionary
    }

    private static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private static func isAppleSiliconCPUKey(_ key: String) -> Bool {
        guard key.count == 4, key.hasPrefix("Tp") else { return false }
        return key.dropFirst(2).allSatisfy { $0.isNumber }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

private final class SMCConnection {
    private var connection: io_connect_t = 0
    private var isOpen = false
    private(set) var openFailureDescription: String?
    private var keyInfoCache: [String: (type: UInt32, size: UInt32)?] = [:]
    private var discoveredKeysCache: [String]?

    func open() -> Bool {
        if isOpen { return true }
        var didFindService = false
        var lastStatus: kern_return_t?
        for serviceName in ["AppleSMC", "AppleSMCKeysEndpoint"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
            guard service != 0 else { continue }
            didFindService = true
            let status = IOServiceOpen(service, mach_task_self_, 0, &connection)
            IOObjectRelease(service)
            if status == kIOReturnSuccess {
                isOpen = true
                openFailureDescription = nil
                return true
            }
            lastStatus = status
        }
        if !didFindService {
            openFailureDescription = "未找到 AppleSMC 服务；此 Mac 或当前系统可能不提供可访问的 SMC 传感器。"
        } else if let lastStatus {
            openFailureDescription = "无法打开 AppleSMC 服务（IOKit 错误 \(lastStatus)）。"
        } else {
            openFailureDescription = "无法打开 AppleSMC 服务。"
        }
        return false
    }

    deinit {
        if isOpen { IOServiceClose(connection) }
    }

    func discoverKeys() -> [String] {
        if let discoveredKeysCache { return discoveredKeysCache }
        guard isOpen else { return [] }

        var countInput = SMCKeyData()
        var countOutput = SMCKeyData()
        countInput.data8 = 4 // kSMCGetKeyCount
        var outputSize = MemoryLayout<SMCKeyData>.size
        let countStatus = IOConnectCallStructMethod(
            connection,
            2,
            &countInput,
            MemoryLayout<SMCKeyData>.size,
            &countOutput,
            &outputSize
        )
        guard countStatus == kIOReturnSuccess, countOutput.data32 > 0, countOutput.data32 < 4096 else {
            discoveredKeysCache = []
            return []
        }

        var keys: [String] = []
        for index in 0..<countOutput.data32 {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.data32 = index
            input.data8 = 8 // kSMCGetKeyFromIndex
            var size = MemoryLayout<SMCKeyData>.size
            guard IOConnectCallStructMethod(
                connection,
                2,
                &input,
                MemoryLayout<SMCKeyData>.size,
                &output,
                &size
            ) == kIOReturnSuccess else { continue }
            let key = fourCharString(output.key)
            if key.count == 4 { keys.append(key) }
        }
        discoveredKeysCache = keys
        return keys
    }

    func readNumber(_ key: String) -> Double? {
        guard isOpen, let info = keyInfo(key) else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = 5
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type

        var outputSize = MemoryLayout<SMCKeyData>.size
        let status = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCKeyData>.size,
            &output,
            &outputSize
        )
        guard status == kIOReturnSuccess else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.size))) }
        return decode(type: info.type, bytes: bytes)
    }

    private func keyInfo(_ key: String) -> (type: UInt32, size: UInt32)? {
        if let cached = keyInfoCache[key] { return cached }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = 9
        var outputSize = MemoryLayout<SMCKeyData>.size
        let status = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCKeyData>.size,
            &output,
            &outputSize
        )
        guard status == kIOReturnSuccess, output.keyInfo.dataSize > 0 else {
            keyInfoCache[key] = nil
            return nil
        }
        let info = (output.keyInfo.dataType, output.keyInfo.dataSize)
        keyInfoCache[key] = info
        return info
    }

    private func decode(type: UInt32, bytes: [UInt8]) -> Double? {
        switch fourCharString(type) {
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int8(bitPattern: bytes[0])) + Double(bytes[1]) / 256
        case "sp87":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(Int(bytes[0]) << 8 | Int(bytes[1]))) / 128
        case "sp5a":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(Int(bytes[0]) << 8 | Int(bytes[1]))) / 1024
        case "fp88":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(Int(bytes[0]) << 8 | Int(bytes[1]))) / 256
        case "fp79":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(Int(bytes[0]) << 8 | Int(bytes[1]))) / 512
        case "fpe4":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 16
        case "ui8 ":
            guard let byte = bytes.first else { return nil }
            return Double(byte)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let value = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(value)
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            // SMC's Apple Silicon `flt ` payload is little-endian. Decoding
            // it as big-endian turns normal fan speeds into tiny floats that
            // round to 0 RPM and makes temperatures disappear as outliers.
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        default:
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        }
    }

    private func fourCharCode(_ value: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in value.utf8.prefix(4) { result = result << 8 | UInt32(byte) }
        for _ in value.utf8.count..<4 { result = result << 8 | 0x20 }
        return result
    }

    private func fourCharString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

let listener = NSXPCListener(machServiceName: SensorServiceConstants.machServiceName)
let delegate = ListenerDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
