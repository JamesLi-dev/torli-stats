import Foundation

enum GPUReader {
    static func usage() -> Double {
        // macOS does not expose GPU utilization through a stable public API.
        // IORegistry gives us a useful local-only fallback on Apple Silicon and Intel Macs.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        // -d 2 does not include PerformanceStatistics on some macOS versions.
        process.arguments = ["-r", "-c", "IOAccelerator", "-d", "4"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return 0 }

            // ioreg changes whitespace around `=` between macOS versions. Parse
            // only the value immediately following the known key; extracting
            // all digits from a larger dictionary can turn an unrelated value
            // into 100%.
            let pattern = #"(Renderer Utilization %|Device Utilization %)"\s*=\s*([0-9]+(?:\.[0-9]+)?)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            var rendererValues: [Double] = []
            var deviceValues: [Double] = []

            for match in regex.matches(in: output, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: output),
                      let valueRange = Range(match.range(at: 2), in: output),
                      let value = Double(output[valueRange]) else { continue }
                if output[keyRange] == "Renderer Utilization %" {
                    rendererValues.append(value)
                } else {
                    deviceValues.append(value)
                }
            }

            // Renderer utilization tracks actual rendering work. Prefer it over
            // the device-level field, which can report 100% while the renderer
            // is idle on some Apple GPU drivers.
            let values = rendererValues.isEmpty ? deviceValues : rendererValues
            guard !values.isEmpty else { return 0 }
            let value = values.reduce(0, +) / Double(values.count)
            return min(100, max(0, value))
        } catch {
            return 0
        }
    }
}
