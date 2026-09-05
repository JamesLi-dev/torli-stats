import Foundation

enum FanReader {
    static func rpm() -> Int? {
        // Apple Silicon 没有公开的风扇 API；powermetrics 需要 root 权限。
        // 如果系统允许无交互读取，则解析其风扇采样，否则返回 nil。
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["-n", "1", "-i", "100"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: output + error, encoding: .utf8) ?? ""
            let pattern = #"(?i)(?:fan|fans).*?([0-9]{3,5})\s*rpm"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[range])
        } catch {
            return nil
        }
    }
}
