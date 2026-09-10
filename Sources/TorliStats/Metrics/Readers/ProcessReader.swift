import Foundation

enum ProcessReader {
    static func topProcesses(limit: Int, sort: ProcessSortOption) -> [ProcessRow] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let rows: [ProcessRow] = output.split(separator: "\n").compactMap { (line: Substring) -> ProcessRow? in
                let fields = line.split(
                    maxSplits: 3,
                    omittingEmptySubsequences: true,
                    whereSeparator: { character in character == " " || character == "\t" }
                )
                guard fields.count == 4 else { return nil }
                guard let pid = Int32(fields[0]),
                      let cpu = Double(fields[1]),
                      let rss = Double(fields[2]) else { return nil }
                let path = String(fields[3])
                let name = URL(fileURLWithPath: path).lastPathComponent
                return ProcessRow(id: pid, name: name, cpu: cpu, memory: rss * 1024)
            }
            .filter { $0.cpu > 0 }

            let sorted: [ProcessRow]
            switch sort {
            case .cpu:
                sorted = rows.sorted { $0.cpu > $1.cpu }
            case .memory:
                sorted = rows.sorted { $0.memory > $1.memory }
            case .combined:
                let maximumCPU = max(rows.map(\.cpu).max() ?? 0, 0.01)
                let maximumMemory = max(rows.map(\.memory).max() ?? 0, 1)
                sorted = rows.sorted {
                    ($0.cpu / maximumCPU + $0.memory / maximumMemory)
                        > ($1.cpu / maximumCPU + $1.memory / maximumMemory)
                }
            }

            return sorted
                .prefix(limit)
                .map { $0 }
        } catch {
            return []
        }
    }
}
