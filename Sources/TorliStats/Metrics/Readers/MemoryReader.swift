import Foundation
import Darwin

enum MemoryPressureLevel {
    case normal
    case warning
    case critical
    case unknown
}

struct MemorySnapshot {
    let percentage: Double
    let used: String
    let total: String
    let pressure: MemoryPressureLevel
}

enum MemoryReader {
    static func snapshot() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let pressure = memoryPressureLevel()
        guard result == KERN_SUCCESS, totalBytes > 0 else {
            return MemorySnapshot(
                percentage: 0,
                used: "—",
                total: format(totalBytes),
                pressure: pressure
            )
        }

        let usedBytes = usedBytes(stats: stats, pageSize: UInt64(vm_page_size), totalBytes: totalBytes)
        return MemorySnapshot(
            percentage: min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100)),
            used: format(usedBytes),
            total: format(totalBytes),
            pressure: pressure
        )
    }

    /// Estimate app + wired + physically compressed memory. Anonymous pages
    /// include inactive app memory; file-backed cache is not counted as app
    /// memory. Subtract purgeable pages without unsigned underflow. Compressor
    /// pages describe physical storage, not the uncompressed logical size.
    /// This is a VM-counter estimate, not an exact Activity Monitor replica.
    static func usedBytes(stats: vm_statistics64, pageSize: UInt64, totalBytes: UInt64) -> UInt64 {
        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = anonymous - min(anonymous, purgeable)
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return min(totalBytes, usedPages * pageSize)
    }

    private static func memoryPressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4, 8: return .critical
        default: return .unknown
        }
    }

    private static func format(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
