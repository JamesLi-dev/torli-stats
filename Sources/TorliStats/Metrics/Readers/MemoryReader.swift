import Foundation
import Darwin

struct MemorySnapshot {
    let percentage: Double
    let used: String
    let total: String
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
        guard result == KERN_SUCCESS, totalBytes > 0 else {
            return MemorySnapshot(percentage: 0, used: "—", total: format(totalBytes))
        }

        let pageSize = UInt64(vm_page_size)
        let reclaimable = UInt64(stats.free_count + stats.inactive_count + stats.speculative_count) * pageSize
        let usedBytes = totalBytes - min(totalBytes, reclaimable)
        return MemorySnapshot(
            percentage: min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100)),
            used: format(usedBytes),
            total: format(totalBytes)
        )
    }

    private static func format(_ bytes: UInt64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
    }
}
