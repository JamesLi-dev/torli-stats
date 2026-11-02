import Foundation

/// All ranges are UTF-16 offsets into one source line, excluding its newline.
struct TaskLine {
    let indentation: String
    let markerRange: NSRange
    let prefixRange: NSRange
    let bodyRange: NSRange
    let body: String
    let completed: Bool
    let markdown: Bool

    var indentationColumns: Int {
        indentation.reduce(0) { $1 == "\t" ? (($0 / 4) + 1) * 4 : $0 + 1 }
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)([☐☑]|[-*+][ \t]+\[([ xX])\](?=[ \t]|$))([ \t]*)([^\r\n]*)"#)

    static func parse(_ source: some StringProtocol) -> TaskLine? {
        let text = String(source) as NSString
        guard let match = pattern.firstMatch(in: text as String,
            range: NSRange(location: 0, length: text.length)) else { return nil }
        let marker = text.substring(with: match.range(at: 2))
        let bodyRange = match.range(at: 5)
        return TaskLine(indentation: text.substring(with: match.range(at: 1)),
                        markerRange: match.range(at: 2),
                        prefixRange: NSRange(location: match.range(at: 2).location,
                                             length: bodyRange.location - match.range(at: 2).location),
                        bodyRange: bodyRange, body: text.substring(with: bodyRange),
                        completed: marker == "☑" || marker.lowercased().contains("[x]"),
                        markdown: marker != "☐" && marker != "☑")
    }

    func marker(toggled: Bool = false) -> String {
        let checked = toggled ? !completed : completed
        return markdown ? (checked ? "- [x]" : "- [ ]") : (checked ? "☑" : "☐")
    }
}

/// Standalone thematic breaks; mixed markers and embedded punctuation are text.
enum MarkdownRule {
    static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let marks = trimmed.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }
}
