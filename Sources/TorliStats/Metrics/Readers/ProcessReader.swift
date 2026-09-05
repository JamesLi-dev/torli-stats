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

            return rows
                .sorted {
                    switch sort {
                    case .cpu: return $0.cpu > $1.cpu
                    case .memory: return $0.memory > $1.memory
                    }
                }
                .prefix(limit)
                .map { $0 }
        } catch {
            return []
        }
    }
}
