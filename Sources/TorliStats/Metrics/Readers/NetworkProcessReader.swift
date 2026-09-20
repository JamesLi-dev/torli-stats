import AppKit
import Foundation

enum NetworkProcessReader {
    /// `nettop` emits a baseline followed by a one-second delta sample. The
    /// second sample contains process-level bytes received and sent during
    /// that interval, without inspecting destinations or packet contents.
    static func topApplications(limit: Int) -> [NetworkApplicationRow] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "2", "-n", "-x", "-d", "-s", "1"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return []
            }
            return parseDeltaSample(output).prefix(limit).map { $0 }
        } catch {
            return []
        }
    }

    static func parseDeltaSample(_ output: String) -> [NetworkApplicationRow] {
        let lines = output.split(whereSeparator: \.isNewline)
        guard let lastHeaderIndex = lines.lastIndex(where: { $0.hasPrefix("time,") }) else {
            return []
        }

        var groups: [String: NetworkApplicationRow] = [:]
        for line in lines.dropFirst(lastHeaderIndex + 1) {
            let fields = csvFields(line)
            guard fields.count > 5,
                  let identity = processIdentity(fields[1]),
                  let received = Double(fields[4]) else {
                continue
            }
            let sent = Double(fields[5]) ?? 0
            guard received > 0 || sent > 0 else { continue }

            let resolved = resolvedApplication(for: identity)
            let existing = groups[resolved.id]
            groups[resolved.id] = NetworkApplicationRow(
                id: resolved.id,
                name: resolved.name,
                download: (existing?.download ?? 0) + received,
                upload: (existing?.upload ?? 0) + sent
            )
        }

        return groups.values.sorted {
            if $0.totalRate == $1.totalRate {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.totalRate > $1.totalRate
        }
    }

    private static func processIdentity(_ field: String) -> (name: String, pid: pid_t)? {
        guard let separator = field.lastIndex(of: "."),
              let pid = pid_t(field[field.index(after: separator)...]) else {
            return nil
        }
        let name = String(field[..<separator])
        guard !name.isEmpty else { return nil }
        return (name, pid)
    }

    private static func resolvedApplication(for process: (name: String, pid: pid_t)) -> (id: String, name: String) {
        let runningApplication = NSRunningApplication(processIdentifier: process.pid)
        let name = canonicalName(runningApplication?.localizedName ?? process.name)
        return (name.lowercased(), name)
    }

    /// Browser and editor helpers typically have a separate process name. For
    /// this display, group their traffic under the parent application's name.
    private static func canonicalName(_ value: String) -> String {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = name.range(of: " Helper", options: [.caseInsensitive]) {
            name = String(name[..<range.lowerBound])
        }
        if let range = name.range(of: " (", options: [.caseInsensitive]) {
            name = String(name[..<range.lowerBound])
        }
        return name.isEmpty ? value : name
    }

    private static func csvFields(_ line: Substring) -> [String] {
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let nextIndex = line.index(after: index)
                if isQuoted, nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    field.append("\"")
                    index = line.index(after: nextIndex)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }
}
