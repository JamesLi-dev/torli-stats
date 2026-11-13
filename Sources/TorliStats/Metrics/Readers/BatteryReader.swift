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
            let health = registry.health ?? design.map { max(0, min(100, maximum / max($0, 1) * 100)) }
                ?? BatteryHealthReader.snapshot()
            let (externalPower, charging) = powerState(description)
            return BatterySnapshot(
                percentage: maximum > 0 ? current / maximum * 100 : 0,
                health: health,
                thermalState: SystemThermalState(ProcessInfo.processInfo.thermalState),
                cycleCount: registry.cycleCount,
                adapterWatts: externalPower ? adapterWatts() : nil,
                isCharging: charging,
                isOnExternalPower: externalPower,
                powerSource: externalPower ? StatsL10n.text("dashboard.power_source.plugged_in") : StatsL10n.text("dashboard.power_source.battery")
            )
        }

        return BatterySnapshot(
            percentage: 100,
            health: nil,
            thermalState: SystemThermalState(ProcessInfo.processInfo.thermalState),
            cycleCount: registry.cycleCount,
            adapterWatts: adapterWatts(),
            isCharging: false,
            isOnExternalPower: true,
            powerSource: StatsL10n.text("dashboard.power_source.plugged_in")
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

    static func powerState(_ description: [String: Any]) -> (externalPower: Bool, charging: Bool) {
        (description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
         (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false)
    }

    private static func registrySnapshot() -> BatteryRegistrySnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedRegistry, now - lastRegistryRead < 60 { return cachedRegistry }
        lastRegistryRead = now

        guard let values = IORegistryReader.properties(matching: "AppleSmartBattery").first else {
            return cachedRegistry ?? BatteryRegistrySnapshot(health: nil, cycleCount: nil)
        }
        let snapshot = BatteryRegistrySnapshot(health: registryHealth(values), cycleCount: (values["CycleCount"] as? NSNumber)?.intValue)
        cachedRegistry = snapshot
        return snapshot
    }

    static func registryHealth(_ values: [String: Any]) -> Double? {
        // Newer systems nest raw capacity counters under BatteryData.
        let batteryData = values["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            (values[key] as? NSNumber)?.doubleValue ?? (batteryData[key] as? NSNumber)?.doubleValue
        }
        if let percent = number("MaximumCapacityPercent"), percent.isFinite {
            return min(100, max(0, percent))
        }
        guard let design = number("DesignCapacity"), design.isFinite, design > 0,
              let full = number("NominalChargeCapacity") ?? number("AppleRawMaxCapacity") ?? number("FullChargeCapacity"),
              full.isFinite else { return nil }
        return min(100, max(0, full / design * 100))
    }
}

private enum BatteryHealthReader {
    private static var cached: Double?
    private static var lastRead: TimeInterval = 0

    static func snapshot() -> Double? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRead < 60 { return cached }
        lastRead = now

        guard let data = BoundedProcess.output("/usr/sbin/system_profiler", arguments: ["SPPowerDataType"], timeout: 5),
              let output = String(data: data, encoding: .utf8) else { return cached }
        let pattern = #"Maximum Capacity:\s*([0-9]+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)),
              let range = Range(match.range(at: 1), in: output),
              let value = Double(output[range]) else { return cached }
        cached = value
        return value
    }
}
