import SwiftUI

/// Compact Todo rendering shared by the deck hover preview and other note
/// summaries. It mirrors the editor's state without exposing Markdown syntax.
struct TaskPreviewLine: View {
    let line: String
    let ink: Color
    let fontSize: CGFloat

    @ViewBuilder
    var body: some View {
        if let task = TaskLine.parse(line) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TaskPreviewCheckbox(isCompleted: task.isCompleted,
                                    color: ink,
                                    size: max(8, fontSize - 1))
                Text(task.body(in: line).trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: fontSize))
                    .strikethrough(task.isCompleted, color: ink.opacity(0.45))
                    .foregroundStyle(ink.opacity(task.isCompleted ? 0.45 : 0.85))
                    .lineLimit(1)
            }
            .padding(.leading, indentationWidth(for: task, line: line))
        } else {
            Text(line)
                .font(.system(size: fontSize))
                .foregroundStyle(ink.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func indentationWidth(for task: TaskLine, line: String) -> CGFloat {
        task.indentation(in: line).reduce(into: CGFloat.zero) { result, character in
            result += character == "\t" ? fontSize * 1.6 : fontSize * 0.35
        }
    }
}

private struct TaskPreviewCheckbox: View {
    let isCompleted: Bool
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(1.5, size * 0.22), style: .continuous)
                .fill(isCompleted ? color.opacity(0.88) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: max(1.5, size * 0.22), style: .continuous)
                        .stroke(color.opacity(isCompleted ? 0.88 : 0.78), lineWidth: 1)
                }
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.68, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .frame(width: size, height: size)
    }
}
