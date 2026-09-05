import AppKit
import SwiftUI

extension TorliAppDelegate {
    func updateStatusBarLogo() {
        guard let button = statusItem?.button else { return }

        let configuration = StatusBarLogoConfiguration(
            isVisible: settings.showStatusBarLogo,
            runner: settings.statusBarRunner,
            acceleratesWithCPU: settings.statusBarLogoAnimation,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        guard configuration != appliedStatusLogoConfiguration else { return }
        appliedStatusLogoConfiguration = configuration
        statusLogoAnimator = nil

        button.image = nil
        button.imagePosition = .noImage

        guard configuration.isVisible else {
            statusLogoImage = nil
            updateStatusTitle(store.statusLine)
            return
        }

        statusLogoAnimator = StatusBarLogoAnimator(
            runner: configuration.runner,
            animated: !configuration.reduceMotion,
            acceleratesWithCPU: configuration.acceleratesWithCPU,
            cpuUsage: store.cpu
        ) { [weak self] image in
            guard let self else { return }
            self.updateStatusBarRunnerImage(image)
        }
    }

    func updateStatusBarLogoSpeed() {
        statusLogoAnimator?.setCPUUsage(store.cpu)
    }

    /// A key press updates several input-stat values. The status bar only
    /// needs a periodic aggregate refresh, rather than one expensive image
    /// composition for every published value.
    func scheduleTypingStatusUpdate() {
        guard settings.showTypingStatusItem,
              settings.typingStatsEnabled,
              settings.statusBarMetricOrder.contains(.typing) else { return }

        // An animated runner already composites the current metric text on
        // its next frame, so a separate input-driven redraw is redundant.
        if settings.showStatusBarLogo,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }

        guard typingStatusUpdateWorkItem == nil else { return }
        let minimumInterval: TimeInterval = 0.4
        let delay = max(0, lastTypingStatusUpdate.addingTimeInterval(minimumInterval).timeIntervalSinceNow)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.typingStatusUpdateWorkItem = nil
            self.lastTypingStatusUpdate = Date()
            self.updateStatusTitle(self.store.statusLine)
        }
        typingStatusUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    private struct StatusBarGroupContent {
        let firstLine: NSAttributedString?
        let secondLine: NSAttributedString?
    }

    private struct CodexStatusBarValue {
        let accountID: UUID
        let prefix: String
        let usedPercent: Double
        let isStale: Bool
    }

    private struct StatusBarTextLayout {
        let image: NSImage
        let runnerOriginX: CGFloat
    }

    private func updateStatusBarRunnerImage(_ image: NSImage?) {
        statusLogoImage = image
        if let statusBarLayeredContentView {
            statusBarLayeredContentView.updateRunnerImage(image)
        } else {
            // The animator can produce its first frame before the static text
            // layout is installed.
            updateStatusTitle(store.statusLine)
        }
    }

    func updateStatusTitle(_ line: StatusLine) {
        guard let button = statusItem.button else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.minimumLineHeight = 10
        style.maximumLineHeight = 10
        let commonAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
            .baselineOffset: -4
        ]

        if let statusLogoImage,
           settings.statusBarMetricOrder.contains(.logo),
           let layout = makeStatusBarTextLayout(
               runnerSize: statusLogoImage.size,
               line: line,
               attributes: commonAttributes,
               appearance: button.effectiveAppearance
           ) {
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString(string: "")

            let contentView: StatusBarLayeredContentView
            if let statusBarLayeredContentView {
                contentView = statusBarLayeredContentView
            } else {
                contentView = StatusBarLayeredContentView(frame: button.bounds)
                contentView.autoresizingMask = [.width, .height]
                button.addSubview(contentView)
                statusBarLayeredContentView = contentView
            }
            statusItem.length = ceil(layout.image.size.width)
            contentView.update(
                textImage: layout.image,
                runnerOriginX: layout.runnerOriginX,
                runnerImage: statusLogoImage
            )
        } else {
            statusBarLayeredContentView?.removeFromSuperview()
            statusBarLayeredContentView = nil
            statusItem.length = NSStatusItem.variableLength
            let groups = settings.statusBarMetricOrder.compactMap {
                normalizedStatusBarGroup(
                    statusBarGroupContent(for: $0, line: line, attributes: commonAttributes),
                    attributes: commonAttributes
                )
            }
            let firstLine = groups.compactMap(\.firstLine)
            let secondLine = groups.compactMap(\.secondLine)
            let attributedTitle = NSMutableAttributedString()

            if !firstLine.isEmpty {
                attributedTitle.append(joinStatusBarSegments(firstLine, attributes: commonAttributes, separator: "  "))
            }
            if !firstLine.isEmpty && !secondLine.isEmpty {
                attributedTitle.append(NSAttributedString(string: "\n", attributes: commonAttributes))
            }
            if !secondLine.isEmpty {
                attributedTitle.append(joinStatusBarSegments(secondLine, attributes: commonAttributes, separator: "  "))
            }
            if attributedTitle.length == 0 {
                attributedTitle.append(NSAttributedString(string: "Torli", attributes: commonAttributes))
            }
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = attributedTitle
        }

        let codexValues = codexStatusBarValues()
        if codexValues.isEmpty {
            button.toolTip = "Torli Stats"
        } else {
            let details = codexValues.map { value in
                let used = Int(min(100, max(0, value.usedPercent)).rounded())
                let remaining = 100 - used
                return "\(value.prefix) · 已使用 \(used)% · 剩余 \(remaining)%"
            }
            button.toolTip = "Torli Stats · Codex · \(details.joined(separator: "；"))"
        }
    }

    private func makeStatusBarTextLayout(
        runnerSize: NSSize,
        line: StatusLine,
        attributes: [NSAttributedString.Key: Any],
        appearance: NSAppearance
    ) -> StatusBarTextLayout? {
        var segments: [(group: StatusBarMetricGroup, content: StatusBarGroupContent?, width: CGFloat)] = []

        for group in settings.statusBarMetricOrder {
            if group == .logo {
                segments.append((group, nil, runnerSize.width))
                continue
            }
            guard let content = normalizedStatusBarGroup(
                statusBarGroupContent(for: group, line: line, attributes: attributes),
                attributes: attributes
            ) else { continue }
            let width = max(content.firstLine?.size().width ?? 0, content.secondLine?.size().width ?? 0)
            segments.append((group, content, width))
        }

        guard !segments.isEmpty else { return nil }
        // Keep status-bar groups compact while leaving a visible separation.
        let spacing: CGFloat = 8
        let totalWidth = segments.reduce(CGFloat.zero) { $0 + $1.width }
            + CGFloat(max(0, segments.count - 1)) * spacing
        guard totalWidth > 0 else { return nil }

        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: 20))
        image.lockFocus()
        var x: CGFloat = 0
        var runnerOriginX: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            for segment in segments {
                if segment.group == .logo {
                    // Leave a transparent runner-sized slot. The runner is a
                    // separate image subview and is the only element updated
                    // for animation frames.
                    runnerOriginX = x
                } else if let content = segment.content {
                    content.firstLine?.draw(at: NSPoint(x: x, y: 10))
                    content.secondLine?.draw(at: NSPoint(x: x, y: 0))
                }
                x += segment.width + spacing
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return StatusBarTextLayout(image: image, runnerOriginX: runnerOriginX)
    }

    private func statusBarGroupContent(
        for group: StatusBarMetricGroup,
        line: StatusLine,
        attributes: [NSAttributedString.Key: Any]
    ) -> StatusBarGroupContent {
        switch group {
        case .system:
            switch settings.systemStatusBarStyle {
            case .compact:
                return StatusBarGroupContent(
                    firstLine: settings.showCPU ? statusBarText("CPU\(rightAligned(line.cpu, width: 5))", attributes: attributes) : nil,
                    secondLine: settings.showMemory ? statusBarText("MEM\(rightAligned(line.memory, width: 5))", attributes: attributes) : nil
                )
            case .stacked:
                let labels = [
                    settings.showCPU ? "CPU" : nil,
                    settings.showMemory ? "MEM" : nil
                ].compactMap { $0 }
                let values = [
                    settings.showCPU ? line.cpu : nil,
                    settings.showMemory ? line.memory : nil
                ].compactMap { $0 }
                return StatusBarGroupContent(
                    firstLine: labels.isEmpty ? nil : statusBarText(leftAlignedStatusBarColumns(labels, columnWidth: 4, separator: " "), attributes: attributes),
                    secondLine: values.isEmpty ? nil : statusBarText(leftAlignedStatusBarColumns(values, columnWidth: 4, separator: " "), attributes: attributes)
                )
            }

        case .network:
            return StatusBarGroupContent(
                firstLine: settings.showUpload ? statusBarText("↑ \(rightAligned(line.upload, width: 8))", attributes: attributes) : nil,
                secondLine: settings.showDownload ? statusBarText("↓ \(rightAligned(line.download, width: 8))", attributes: attributes) : nil
            )

        case .logo:
            // Logo is composed with the two-line text groups as one image in
            // `updateStatusTitle`, allowing it to be placed at any position.
            return StatusBarGroupContent(firstLine: nil, secondLine: nil)

        case .typing:
            guard settings.showTypingStatusItem,
                  settings.typingStatsEnabled,
                  typingStats.permissionStatus == .monitoring else {
                return StatusBarGroupContent(firstLine: nil, secondLine: nil)
            }
            return StatusBarGroupContent(
                firstLine: statusBarText("输入", attributes: attributes),
                secondLine: statusBarText("\(compactTypingCount(typingStats.todayKeyCount))键", attributes: attributes)
            )

        case .codex:
            let values = codexStatusBarValues()
            guard !values.isEmpty else {
                return StatusBarGroupContent(firstLine: nil, secondLine: nil)
            }
            let labels = values.map { statusBarText($0.isStale ? "\($0.prefix)!" : $0.prefix, attributes: attributes) }
            let percentages = values.map { value in
                let used = Int(min(100, max(0, value.usedPercent)).rounded())
                let remaining = 100 - used
                let displayed = settings.codexStatusMetric == .used ? used : remaining
                return statusBarText(
                    "\(displayed)%",
                    attributes: attributes.merging([
                        .foregroundColor: value.isStale ? NSColor.systemOrange : codexStatusColor(usedPercent: value.usedPercent)
                    ]) { _, new in new }
                )
            }
            // Use the same width for each account's name and percentage
            // column. Without this, a three-character name followed by a
            // four-character value shifts the next account by one character.
            let columnWidths = zip(labels, percentages).map { label, percentage in
                max(label.string.count, percentage.string.count)
            }
            return StatusBarGroupContent(
                firstLine: joinStatusBarColumns(labels, widths: columnWidths, attributes: attributes),
                secondLine: joinStatusBarColumns(percentages, widths: columnWidths, attributes: attributes)
            )
        }
    }

    private func codexStatusBarValues() -> [CodexStatusBarValue] {
        let statusBarAccounts = codexUsageStore.accounts.filter(\.isStatusBarIncluded)
        let values = statusBarAccounts.enumerated().compactMap { index, account -> CodexStatusBarValue? in
            guard let snapshot = codexUsageStore.state(for: account.id).snapshot,
                  let primary = snapshot.primary else {
                return nil
            }
            return CodexStatusBarValue(
                accountID: account.id,
                prefix: settings.privacyMode ? "COD\(index + 1)" : snapshot.account.displayPrefix,
                usedPercent: primary.usedPercent,
                isStale: snapshot.isStale()
            )
        }

        switch settings.codexStatusBarMode {
        case .defaultAccount:
            return values.filter { $0.accountID == CodexAccountConfiguration.defaultAccountID }
        case .lowestRemaining:
            guard let lowestRemaining = values.max(by: { $0.usedPercent < $1.usedPercent }) else { return [] }
            return [CodexStatusBarValue(accountID: lowestRemaining.accountID, prefix: "COD", usedPercent: lowestRemaining.usedPercent, isStale: lowestRemaining.isStale)]
        case .eachAccount:
            return values
        }
    }

    private func statusBarText(_ value: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: value, attributes: attributes)
    }

    private func leftAlignedStatusBarColumns(
        _ values: [String],
        columnWidth: Int = 6,
        separator: String = "  "
    ) -> String {
        values.enumerated().map { index, value in
            guard index < values.count - 1 else { return value }
            return value + String(repeating: " ", count: max(1, columnWidth - value.count))
        }.joined(separator: separator)
    }

    private func normalizedStatusBarGroup(
        _ group: StatusBarGroupContent,
        attributes: [NSAttributedString.Key: Any]
    ) -> StatusBarGroupContent? {
        guard group.firstLine != nil || group.secondLine != nil else { return nil }
        let width = max(group.firstLine?.string.count ?? 0, group.secondLine?.string.count ?? 0)
        let firstLine = group.firstLine.map { segment in
            paddedStatusBarSegment(segment, width: width, attributes: attributes)
        } ?? statusBarText(String(repeating: " ", count: width), attributes: attributes)
        let secondLine = group.secondLine.map { segment in
            paddedStatusBarSegment(segment, width: width, attributes: attributes)
        } ?? statusBarText(String(repeating: " ", count: width), attributes: attributes)
        return StatusBarGroupContent(firstLine: firstLine, secondLine: secondLine)
    }

    private func paddedStatusBarSegment(
        _ segment: NSAttributedString,
        width: Int,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: segment)
        let padding = max(0, width - segment.string.count)
        if padding > 0 {
            result.append(NSAttributedString(string: String(repeating: " ", count: padding), attributes: attributes))
        }
        return result
    }

    private func joinStatusBarColumns(
        _ segments: [NSAttributedString],
        widths: [Int],
        attributes: [NSAttributedString.Key: Any],
        separator: String = "  "
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: separator, attributes: attributes))
            }
            let width = widths.indices.contains(index) ? widths[index] : segment.string.count
            result.append(paddedStatusBarSegment(segment, width: width, attributes: attributes))
        }
        return result
    }

    private func joinStatusBarSegments(
        _ segments: [NSAttributedString],
        attributes: [NSAttributedString.Key: Any],
        separator: String = "  "
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: separator, attributes: attributes))
            }
            result.append(segment)
        }
        return result
    }

    private func compactTypingCount(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000) : String(value)
    }

    private func codexStatusColor(usedPercent: Double) -> NSColor {
        let remaining = 100 - usedPercent
        if remaining < 20 { return .systemRed }
        if remaining <= 50 { return .systemOrange }
        return .systemGreen
    }

    private func rightAligned(_ value: String, width: Int) -> String {
        let padding = max(0, width - value.count)
        return String(repeating: " ", count: padding) + value
    }
}
