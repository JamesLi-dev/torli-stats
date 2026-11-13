import Foundation

enum GPUReader {
    static func usage() -> Double {
        utilization(IORegistryReader.properties(matching: "IOAccelerator", recursive: true))
    }

    static func utilization(_ entries: [[String: Any]]) -> Double {
        let statistics = entries.compactMap { $0["PerformanceStatistics"] as? [String: Any] }
        let renderer = statistics.compactMap { ($0["Renderer Utilization %"] as? NSNumber)?.doubleValue }.filter(\.isFinite)
        let device = statistics.compactMap { ($0["Device Utilization %"] as? NSNumber)?.doubleValue }.filter(\.isFinite)
        let values = renderer.isEmpty ? device : renderer
        guard !values.isEmpty else { return 0 }
        return min(100, max(0, values.reduce(0, +) / Double(values.count)))
    }
}
