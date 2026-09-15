import Foundation

/// The source ranges that make up an inline plain-text Todo line.
///
/// Ranges use UTF-16 offsets so they can be applied directly to NSTextStorage
/// and NSString values. The note body remains plain text; this model only gives
/// every consumer one interpretation of its task prefix.
struct TaskLine: Equatable {
    enum State: Equatable {
        case open
        case completed
    }

    let indentationRange: NSRange
    let checkboxRange: NSRange
    let separatorRange: NSRange
    let bodyRange: NSRange
    let state: State

    var isCompleted: Bool { state == .completed }
    var isEmpty: Bool { bodyRange.length == 0 }

    /// The checkbox and the whitespace after it, excluding indentation.
    /// Removing this range turns a task back into an ordinary indented line.
    var taskPrefixRange: NSRange {
        NSRange(location: checkboxRange.location,
                length: NSMaxRange(separatorRange) - checkboxRange.location)
    }

    var marker: Character {
        isCompleted ? "☑" : "☐"
    }

    /// Parse an internal note line beginning with optional spaces/tabs and a
    /// Unicode checkbox. A line ending is ignored when calculating bodyRange.
    static func parse(_ line: String) -> TaskLine? {
        let text = line as NSString
        let contentLength = contentLength(of: text)
        let indentation = leadingIndentationRange(in: line)
        let markerLocation = NSMaxRange(indentation)
        guard markerLocation < contentLength else { return nil }

        let code = text.character(at: markerLocation)
        let state: State
        switch code {
        case 0x2610: state = .open
        case 0x2611: state = .completed
        default: return nil
        }

        let checkbox = NSRange(location: markerLocation, length: 1)
        var bodyLocation = NSMaxRange(checkbox)
        while bodyLocation < contentLength,
              isHorizontalWhitespace(text.character(at: bodyLocation)) {
            bodyLocation += 1
        }

        return TaskLine(
            indentationRange: indentation,
            checkboxRange: checkbox,
            separatorRange: NSRange(location: NSMaxRange(checkbox),
                                     length: bodyLocation - NSMaxRange(checkbox)),
            bodyRange: NSRange(location: bodyLocation,
                               length: contentLength - bodyLocation),
            state: state
        )
    }

    /// The leading spaces/tabs of any line, including a non-task line.
    static func leadingIndentationRange(in line: String) -> NSRange {
        let text = line as NSString
        var length = 0
        while length < text.length,
              isHorizontalWhitespace(text.character(at: length)) {
            length += 1
        }
        return NSRange(location: 0, length: length)
    }

    func indentation(in line: String) -> String {
        substring(in: line, range: indentationRange)
    }

    func body(in line: String) -> String {
        substring(in: line, range: bodyRange)
    }

    func separator(in line: String) -> String {
        substring(in: line, range: separatorRange)
    }

    private func substring(in line: String, range: NSRange) -> String {
        let text = line as NSString
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= text.length else { return "" }
        return text.substring(with: range)
    }

    private static func contentLength(of text: NSString) -> Int {
        var length = text.length
        guard length > 0 else { return 0 }

        if text.character(at: length - 1) == 0x0A {
            length -= 1
            if length > 0, text.character(at: length - 1) == 0x0D {
                length -= 1
            }
        } else if text.character(at: length - 1) == 0x0D {
            length -= 1
        }
        return length
    }

    private static func isHorizontalWhitespace(_ value: unichar) -> Bool {
        value == 0x20 || value == 0x09
    }
}
