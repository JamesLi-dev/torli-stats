import Foundation

struct DiskSnapshot {
    let usage: Double
    let total: UInt64
    let free: UInt64
}

enum DiskReader {
    static func snapshot() -> DiskSnapshot {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attributes[.systemSize] as? NSNumber)?.uint64Value ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
            let usage = total > 0 ? Double(total - min(total, free)) / Double(total) * 100 : 0
            return DiskSnapshot(usage: usage, total: total, free: free)
        } catch {
            return DiskSnapshot(usage: 0, total: 0, free: 0)
        }
    }
}
