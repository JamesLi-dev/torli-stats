import Foundation
import Darwin

struct DeviceInfo {
    let model: String
    let cpuModel: String
    let gpuModel: String
    let gpuCores: Int?
    let memory: String
    let system: String
    var uptime: String

    static func placeholder() -> DeviceInfo {
        DeviceInfo(
            model: "Mac",
            cpuModel: "未知 CPU",
            gpuModel: "未知 GPU",
            gpuCores: nil,
            memory: "—",
            system: "macOS",
            uptime: uptimeString()
        )
    }

    static func current() -> DeviceInfo {
        let hardware = systemProfiler("SPHardwareDataType")
        let displays = systemProfiler("SPDisplaysDataType")
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            model: modelName(from: hardware),
            cpuModel: value(for: "Chip:", in: hardware)
                ?? value(for: "Processor Name:", in: hardware)
                ?? hardwareIdentifier(),
            gpuModel: value(for: "Chipset Model:", in: displays) ?? "未知 GPU",
            gpuCores: coreCount(in: displays),
            memory: formatMemory(ProcessInfo.processInfo.physicalMemory),
            system: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            uptime: uptimeString()
        )
    }

    static func uptimeString() -> String {
        var remaining = Int(ProcessInfo.processInfo.systemUptime)
        let days = remaining / 86_400
        remaining %= 86_400
        let hours = remaining / 3_600
        remaining %= 3_600
        let minutes = remaining / 60

        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        return "\(minutes)分钟"
    }

    private static func formatMemory(_ bytes: UInt64) -> String {
        // macOS 展示内存容量使用 GiB 口径，64 GiB 不应显示成 69 GB。
        String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
    }

    private static func systemProfiler(_ dataType: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = [dataType]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func value(for key: String, in output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let value = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func coreCount(in output: String) -> Int? {
        guard let value = value(for: "Total Number of Cores:", in: output) else { return nil }
        let digits = value.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func modelName(from hardware: String) -> String {
        if let model = value(for: "Model Name:", in: hardware) { return model }

        let identifier = hardwareIdentifier()
        switch identifier {
        case let value where value.hasPrefix("MacBookPro"): return "MacBook Pro"
        case let value where value.hasPrefix("MacBookAir"): return "MacBook Air"
        case let value where value.hasPrefix("Macmini"): return "Mac mini"
        case let value where value.hasPrefix("MacPro"): return "Mac Pro"
        case let value where value.hasPrefix("iMac"): return "iMac"
        default: return identifier.isEmpty ? "Mac" : identifier
        }
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return "" }
        return String(cString: value)
    }
}
