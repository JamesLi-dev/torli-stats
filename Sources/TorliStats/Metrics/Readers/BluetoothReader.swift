import Foundation

enum BluetoothReader {
    // system_profiler is relatively expensive to launch. Bluetooth battery
    // levels are intentionally cached between low-frequency refreshes.
    private static var cached: [BluetoothBatterySnapshot] = []
    private static var lastReadTime: TimeInterval = 0
    private static let cacheDuration: TimeInterval = 60

    static func snapshot() -> [BluetoothBatterySnapshot] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReadTime < cacheDuration { return cached }
        lastReadTime = now

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return cached }
            cached = parse(output)
            return cached
        } catch {
            return cached
        }
    }

    private static func parse(_ output: String) -> [BluetoothBatterySnapshot] {
        var snapshots: [BluetoothBatterySnapshot] = []
        var connectedSection = false
        var currentName: String?
        var currentConnected = false
        var majorType = ""
        var minorType = ""
        var left: Double?
        var right: Double?
        var single: Double?

        func flush() {
            guard let currentName,
                  currentConnected,
                  let level = single ?? average(left, right) else { return }

            let detail: String
            if let left, let right {
                detail = "左 \(Int(left))%  ·  右 \(Int(right))%"
            } else if let left {
                detail = "左 \(Int(left))%"
            } else if let right {
                detail = "右 \(Int(right))%"
            } else {
                detail = "电量 \(Int(level))%"
            }
            snapshots.append(BluetoothBatterySnapshot(
                name: currentName,
                percentage: level,
                detail: detail,
                kind: BluetoothDeviceKind.detect(
                    name: currentName,
                    majorType: majorType,
                    minorType: minorType
                )
            ))
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(rawLine)
            let value = raw.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            let indentation = raw.prefix { $0 == " " || $0 == "\t" }.count

            if value == "Connected:" {
                flush()
                currentName = nil
                currentConnected = false
                majorType = ""
                minorType = ""
                left = nil
                right = nil
                single = nil
                connectedSection = true
                continue
            }
            if value == "Not Connected:" {
                flush()
                currentName = nil
                currentConnected = false
                connectedSection = false
                continue
            }

            // system_profiler emits device names as an indented `Name:` line,
            // while properties such as `Battery Level:` are indented further.
            // Treat only non-property headers as device boundaries so several
            // connected devices can be collected independently.
            if indentation <= 12,
               value.hasSuffix(":"),
               !propertyPrefixes.contains(where: { value.hasPrefix($0) }) {
                flush()
                currentName = String(value.dropLast()).trimmingCharacters(in: .whitespaces)
                currentConnected = connectedSection
                majorType = ""
                minorType = ""
                left = nil
                right = nil
                single = nil
                continue
            }

            guard currentName != nil else { continue }
            if let type = string(after: "Major Type:", in: value) {
                majorType = type
            } else if let type = string(after: "Minor Type:", in: value) {
                minorType = type
            } else if let connected = connectionValue(in: value) {
                currentConnected = connected
            } else if let level = percentage(after: "Left Battery Level:", in: value) {
                left = level
            } else if let level = percentage(after: "Right Battery Level:", in: value) {
                right = level
            } else if let level = percentage(after: "Battery Level:", in: value) {
                single = level
            }
        }
        flush()
        return snapshots
    }

    private static let propertyPrefixes = [
        "Address:", "Major Type:", "Minor Type:", "Services:", "Paired:",
        "Configured:", "Connected:", "Firmware Version:", "Battery Level:",
        "Left Battery Level:", "Right Battery Level:"
    ]

    private static func connectionValue(in value: String) -> Bool? {
        guard value.hasPrefix("Connected:") else { return nil }
        let suffix = value.dropFirst("Connected:".count)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if suffix.isEmpty { return true }
        if suffix == "yes" || suffix == "true" { return true }
        if suffix == "no" || suffix == "false" { return false }
        return nil
    }

    private static func average(_ left: Double?, _ right: Double?) -> Double? {
        switch (left, right) {
        case let (left?, right?): return (left + right) / 2
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }

    private static func string(after key: String, in value: String) -> String? {
        guard value.hasPrefix(key) else { return nil }
        return String(value.dropFirst(key.count).trimmingCharacters(in: .whitespaces))
    }

    private static func percentage(after key: String, in value: String) -> Double? {
        guard value.hasPrefix(key) else { return nil }
        let suffix = value.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return Double(suffix.replacingOccurrences(of: "%", with: ""))
    }
}
