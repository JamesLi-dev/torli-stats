import Foundation
import IOKit.ps

private struct BatteryRegistrySnapshot {
    let health: Double?
    let cycleCount: Int?
}

enum BatteryReader {
    private static var cachedRegistry: BatteryRegistrySnapshot?
    private static var lastRegistryRead: TimeInterval = 0

    static func snapshot() -> BatterySnapshot {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let registry = registrySnapshot()

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let design = (description[kIOPSDesignCapacityKey] as? NSNumber)?.doubleValue
            let health = design.map { max(0, min(100, maximum / max($0, 1) * 100)) }
                ?? BatteryHealthReader.snapshot() ?? registry.health
            let state = description[kIOPSPowerSourceStateKey] as? String ?? ""
            let charging = state == kIOPSACPowerValue
            return BatterySnapshot(
                percentage: maximum > 0 ? current / maximum * 100 : 0,
                health: health,
                cycleCount: registry.cycleCount,
                adapterWatts: charging ? adapterWatts() : nil,
                isCharging: charging,
                powerSource: charging ? "电源供电" : "电池"
            )
        }

        return BatterySnapshot(
            percentage: 100,
            health: nil,
            cycleCount: registry.cycleCount,
            adapterWatts: adapterWatts(),
            isCharging: true,
            powerSource: "电源供电"
        )
    }

    private static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = (details[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue,
              watts > 0 else {
            return nil
        }
        return watts
    }

    private static func registrySnapshot() -> BatteryRegistrySnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedRegistry, now - lastRegistryRead < 60 { return cachedRegistry }
        lastRegistryRead = now

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-c", "AppleSmartBattery", "-d", "2"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return cachedRegistry ?? BatteryRegistrySnapshot(health: nil, cycleCount: nil)
            }
            let design = registryValue("DesignCapacity", in: output)
            let fullCharge = registryValue("NominalChargeCapacity", in: output)
                ?? registryValue("AppleRawMaxCapacity", in: output)
            let health: Double? = if let design, let fullCharge, design > 0 {
                max(0, min(100, fullCharge / design * 100))
            } else {
                nil
            }
            let cycleCount = registryValue("CycleCount", in: output).map(Int.init)
            let snapshot = BatteryRegistrySnapshot(health: health, cycleCount: cycleCount)
            cachedRegistry = snapshot
            return snapshot
        } catch {
            return cachedRegistry ?? BatteryRegistrySnapshot(health: nil, cycleCount: nil)
        }
    }

    private static func registryValue(_ key: String, in output: String) -> Double? {
        // ioreg may change indentation and spacing around `=`. Parse the
        // key/value pair itself instead of relying on a particular line shape.
        let pattern = #"\"\#(key)\"\s*=\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output)
              ),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[range])
    }
}

private enum BatteryHealthReader {
    private static var cached: Double?
    private static var lastRead: TimeInterval = 0

    static func snapshot() -> Double? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRead < 60 { return cached }
        lastRead = now

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return cached }
            let pattern = #"Maximum Capacity:\s*([0-9]+)%"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)),
                  let range = Range(match.range(at: 1), in: output),
                  let value = Double(output[range]) else { return cached }
            cached = value
            return value
        } catch {
            return cached
        }
    }
}
