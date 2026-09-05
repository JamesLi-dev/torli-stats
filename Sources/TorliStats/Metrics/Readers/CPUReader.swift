import Foundation
import Darwin

struct CPUSnapshot {
    let total: Double
    let perCore: [Double]
}

struct CPUSampler {
    private var previous: [UInt64]?

    mutating func sample() -> CPUSnapshot {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else {
            return CPUSnapshot(total: 0, perCore: [])
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: processorInfo),
                vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        let coreCount = Int(processorCount)
        var current = Array(repeating: UInt64(0), count: coreCount * Int(CPU_STATE_MAX))
        for core in 0..<coreCount {
            let offset = core * Int(CPU_STATE_MAX)
            for state in 0..<Int(CPU_STATE_MAX) {
                current[offset + state] = UInt64(processorInfo[offset + state])
            }
        }

        // The first sample only establishes a baseline. A processor can also
        // be added/removed while the app is running, so reset in that case.
        guard let previous, previous.count == current.count else {
            self.previous = current
            return CPUSnapshot(total: 0, perCore: Array(repeating: 0, count: coreCount))
        }
        self.previous = current

        var perCore: [Double] = []
        perCore.reserveCapacity(coreCount)
        var busyTicks: UInt64 = 0
        var totalTicks: UInt64 = 0

        for core in 0..<coreCount {
            let offset = core * Int(CPU_STATE_MAX)
            let user = current[offset + Int(CPU_STATE_USER)] - previous[offset + Int(CPU_STATE_USER)]
            let system = current[offset + Int(CPU_STATE_SYSTEM)] - previous[offset + Int(CPU_STATE_SYSTEM)]
            let nice = current[offset + Int(CPU_STATE_NICE)] - previous[offset + Int(CPU_STATE_NICE)]
            let idle = current[offset + Int(CPU_STATE_IDLE)] - previous[offset + Int(CPU_STATE_IDLE)]
            let busy = user + system + nice
            let total = busy + idle
            busyTicks += busy
            totalTicks += total
            perCore.append(total > 0 ? min(100, Double(busy) / Double(total) * 100) : 0)
        }

        let overall = totalTicks > 0 ? Double(busyTicks) / Double(totalTicks) * 100 : 0
        return CPUSnapshot(total: min(100, max(0, overall)), perCore: perCore)
    }
}
