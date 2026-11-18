import AppKit
import SwiftUI

private struct UpdateAppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct UpdateCheckView: View {
    @ObservedObject var controller: UpdateCheckController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                UpdateAppIcon(size: 42)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: controller.result?.title ?? StatsL10n.text("update.checking"))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let result = controller.result {
                        Text(verbatim: result.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(StatsL10n.text(controller.result == nil ? "update.install.cancel" : "update.check.close")) {
                    controller.close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Only block structure is interpreted. Text is always verbatim: release content
// cannot load images, execute HTML, or create actionable embedded links.
struct UpdateReleaseNoteLine: Equatable {
    enum Kind: Equatable {
        case heading
        case bullet
        case paragraph
        case code
    }

    let kind: Kind
    let text: String

    static func parse(_ notes: String) -> [Self] {
        var result: [Self] = []
        var fence: String?
        for rawLine in notes.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = String(line.prefix(3))
                if fence == marker {
                    fence = nil
                } else if fence == nil {
                    fence = marker
                } else {
                    result.append(Self(kind: .code, text: String(rawLine)))
                }
                continue
            }
            if fence != nil {
                result.append(Self(kind: .code, text: String(rawLine)))
                continue
            }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first?.isWhitespace == true {
                result.append(Self(kind: .heading, text: String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)))
            } else if let first = line.first, "-*+".contains(first), line.dropFirst().first?.isWhitespace == true {
                result.append(Self(kind: .bullet, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                result.append(Self(kind: .paragraph, text: line))
            }
        }
        return result
    }
}

private struct UpdateReleaseNotesView: View {
    let state: UpdateInstallationController.NotesState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch state {
                case .loading:
                    Text(StatsL10n.text("update.notes.loading"))
                        .foregroundStyle(.secondary)
                case let .loaded(lines):
                    if lines.isEmpty {
                        Text(StatsL10n.text("update.notes.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lines.indices, id: \.self) { index in
                            lineView(lines[index])
                        }
                    }
                case .failed:
                    Text(StatsL10n.text("update.notes.failed"))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .textSelection(.enabled)
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func lineView(_ line: UpdateReleaseNoteLine) -> some View {
        switch line.kind {
        case .heading:
            Text(verbatim: line.text)
                .font(.headline)
                .padding(.top, 4)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(verbatim: "•")
                Text(verbatim: line.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph:
            Text(verbatim: line.text)
        case .code:
            Text(verbatim: line.text)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct UpdatePreparationView: View {
    let progress: UpdatePreparationProgress
    let onCancel: () -> Void

    private var title: String {
        switch progress {
        case .preparing: return StatsL10n.text("update.install.preparing")
        case .downloading: return StatsL10n.text("update.install.downloading")
        case .verifying: return StatsL10n.text("update.install.verifying")
        case .homebrew: return StatsL10n.text("update.install.homebrew")
        }
    }

    private var fraction: Double? {
        guard case let .downloading(received, total) = progress, let total, total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }

    private var detail: String? {
        guard case let .downloading(received, total) = progress else { return nil }
        let receivedText = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        if let total, total > 0 {
            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let percent = Int(min(1, max(0, Double(received) / Double(total))) * 100)
            return StatsL10n.format("update.install.download_progress", receivedText, totalText, Int64(percent))
        }
        return StatsL10n.format("update.install.download_received", receivedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                UpdateAppIcon(size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    if let detail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(StatsL10n.text("update.install.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

struct UpdateInstallationView: View {
    @ObservedObject var controller: UpdateInstallationController

    var body: some View {
        Group {
            switch controller.state {
            case .details:
                details
            case .preparing:
                UpdatePreparationView(progress: controller.progress, onCancel: controller.cancel)
            case .prepared:
                ready
            case let .failed(message):
                failure(message)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                title: StatsL10n.format("update.alert.title", controller.release.version),
                subtitle: StatsL10n.format("update.version.transition", controller.currentVersion, controller.release.version),
                iconSize: 46
            )
            Text(StatsL10n.text("update.notes.title"))
                .font(.subheadline.weight(.semibold))
            UpdateReleaseNotesView(state: controller.notesState)
                .frame(minHeight: 100, maxHeight: .infinity)
            actions(showReleaseLink: true)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(
                title: StatsL10n.text(controller.usesHomebrew ? "update.install.homebrew_ready" : "update.install.ready"),
                subtitle: StatsL10n.text(controller.usesHomebrew ? "update.install.homebrew_ready_detail" : "update.install.ready_detail")
            )
            Spacer(minLength: 0)
            actions(showReleaseLink: false)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: StatsL10n.text("update.install.failed_title"))
            ScrollView {
                Text(verbatim: StatsL10n.format("update.install.failed", message))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            actions(showReleaseLink: true)
        }
    }

    private func header(title: String, subtitle: String? = nil, iconSize: CGFloat = 42) -> some View {
        HStack(alignment: .top, spacing: 14) {
            UpdateAppIcon(size: iconSize)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actions(showReleaseLink: Bool) -> some View {
        HStack(spacing: 10) {
            if showReleaseLink && PrivateUpdateChannel.current == nil {
                Link(StatsL10n.text("update.alert.download"), destination: controller.release.downloadURL)
            }
            Spacer(minLength: 0)
            Button(StatsL10n.text("update.alert.later")) { controller.cancel() }
                .keyboardShortcut(.cancelAction)
            Button(controller.actionTitle) { controller.install() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
