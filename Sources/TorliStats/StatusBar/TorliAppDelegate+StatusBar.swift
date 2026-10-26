import AppKit
import SwiftUI

extension TorliAppDelegate {
    func updateStatusBarLogo() {
        guard let button = statusItem?.button else { return }

        let configuration = StatusBarLogoConfiguration(
            isVisible: settings.showStatusBarLogo,
            isAnimated: settings.statusBarLogoAnimated,
            staticLogo: settings.statusBarStaticLogo,
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

        guard configuration.isAnimated else {
            statusLogoImage = configuration.staticLogo.makeImage()
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
        statusLogoAnimator?.setPaused(monitoringPauseController.mode != .realtime)
        // Install the static title once after the animator has produced its
        // initial frame. Later frames update only the native image.
        updateStatusTitle(store.statusLine)
    }

    func updateStatusBarLogoSpeed() {
        statusLogoAnimator?.setPaused(monitoringPauseController.mode != .realtime)
        statusLogoAnimator?.setCPUUsage(store.cpu)
    }

    /// A key press updates several input-stat values. The status bar only
    /// needs a periodic aggregate refresh, rather than one title rebuild for
    /// every published value.
    func scheduleTypingStatusUpdate() {
        guard settings.showTypingStatusItem,
              settings.typingStatsEnabled,
              settings.statusBarMetricOrder.contains(.typing) else { return }

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

    private func updateStatusBarRunnerImage(_ image: NSImage?) {
        statusLogoImage = image

        // Rebuilding the attributed title for every animation frame forces
        // AppKit to typeset and snapshot the complete status item. The title
        // changes only with metrics or settings; an animation frame needs to
        // replace the native runner image alone.
        guard settings.showStatusBarLogo,
              settings.statusBarMetricOrder.contains(.logo),
              let button = statusItem?.button,
              button.image !== image else {
            return
        }
        installRunnerFrame(image, in: button)
    }

    private func installRunnerFrame(_ image: NSImage?, in button: NSStatusBarButton) {
        guard let image else { return }
        if !settings.statusBarLogoAnimated {
            button.subviews.compactMap { $0 as? StatusBarRunnerImageView }.forEach { $0.removeFromSuperview() }
            if button.image !== image { button.image = image }
            return
        }
        let runnerView: StatusBarRunnerImageView
        if let existing = button.subviews.compactMap({ $0 as? StatusBarRunnerImageView }).first {
            runnerView = existing
        } else {
            runnerView = StatusBarRunnerImageView(frame: .zero)
            runnerView.wantsLayer = true
            runnerView.imageScaling = .scaleProportionallyDown
            button.addSubview(runnerView)
        }
        // Reserve native image layout once. Only the small child layer changes
        // between frames; the native button's title stays cached by AppKit.
        if runnerView.image?.size != image.size || button.image == nil {
            button.image = NSImage(size: image.size, flipped: false) { _ in true }
        }
        runnerView.image = image
        runnerView.contentTintColor = image.isTemplate ? .labelColor : nil
        runnerView.frame = button.cell?.imageRect(forBounds: button.bounds) ?? .zero
    }

    func updateStatusTitle(_ line: StatusLine) {
        guard let button = statusItem.button else { return }

        let fontSize = settings.statusBarFontSize.pointSize
        let lineHeight = fontSize + 1
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        let commonAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style,
            .baselineOffset: -max(0, fontSize - 5)
        ]

        if statusItem.length != NSStatusItem.variableLength {
            statusItem.length = NSStatusItem.variableLength
        }
        let includesRunner = settings.showStatusBarLogo
            && settings.statusBarMetricOrder.contains(.logo)
            && statusLogoImage != nil
        if includesRunner {
            if button.imagePosition != runnerImagePosition {
                button.imagePosition = runnerImagePosition
            }
            // Keep image and title adjacent as one native button content group.
            // The sprite's transparent side padding is trimmed before it reaches
            // AppKit, so the standard image/title gap remains visually compact.
            if !button.imageHugsTitle { button.imageHugsTitle = true }
        } else {
            button.subviews.compactMap { $0 as? StatusBarRunnerImageView }.forEach { $0.removeFromSuperview() }
            if button.image != nil { button.image = nil }
            if button.imagePosition != .noImage { button.imagePosition = .noImage }
            if button.imageHugsTitle { button.imageHugsTitle = false }
        }

        let groups = settings.statusBarMetricOrder.compactMap { group -> StatusBarGroupContent? in
            guard group != .logo else { return nil }
            let content = statusBarGroupContent(for: group, line: line, attributes: commonAttributes)
            return content.firstLine != nil || content.secondLine != nil ? content : nil
        }
        let attributedTitle = NSMutableAttributedString(attributedString: StatusBarTextLayout.title(
            top: groups.map { $0.firstLine ?? NSAttributedString() },
            bottom: groups.map { $0.secondLine ?? NSAttributedString() },
            attributes: commonAttributes,
            gap: statusBarSeparator("  ", attributes: commonAttributes).size().width,
            leadingInset: includesRunner ? statusBarSeparator("  ", attributes: commonAttributes).size().width : 0
        ))
        if attributedTitle.length == 0 && !includesRunner {
            attributedTitle.append(NSAttributedString(string: "Torli", attributes: commonAttributes))
        }
        if !button.attributedTitle.isEqual(to: attributedTitle) {
            button.attributedTitle = attributedTitle
        }

        if includesRunner { installRunnerFrame(statusLogoImage, in: button) }

        var tooltipLines: [String] = []
        if settings.showTypingStatusItem,
           settings.typingStatsEnabled,
           settings.statusBarMetricOrder.contains(.typing),
           typingStats.permissionStatus == .monitoring {
            let count = typingStats.todayKeyCount.formatted(.number)
            tooltipLines.append(StatsL10n.format("status_bar.typing.tooltip", count))
        }
        let codexValues = codexStatusBarValues()
        if !codexValues.isEmpty {
            let details = codexValues.map { value in
                let used = Int(min(100, max(0, value.usedPercent)).rounded())
                let remaining = 100 - used
                return StatsL10n.format("status_bar.codex.tooltip.detail", value.prefix, used, remaining)
            }
            tooltipLines.append(StatsL10n.format("status_bar.codex.tooltip", details.joined(separator: StatsL10n.text("status_bar.codex.tooltip.separator"))))
        }
        let tooltip = tooltipLines.isEmpty ? "Torli Stats" : tooltipLines.joined(separator: "\n")
        if button.toolTip != tooltip { button.toolTip = tooltip }
    }

    private var runnerImagePosition: NSControl.ImagePosition {
        let order = settings.statusBarMetricOrder
        guard let runnerIndex = order.firstIndex(of: .logo) else { return .imageLeading }
        let groupsBeforeRunner = runnerIndex
        let groupsAfterRunner = max(0, order.count - runnerIndex - 1)
        return groupsBeforeRunner <= groupsAfterRunner ? .imageLeading : .imageTrailing
    }

    private struct FormattedNetworkRate {
        let number: String
        let unit: String
    }

    /// Keep the unit immediately after a fixed-width numeric field: e.g.
    /// ` 28.1 KB/s` and `123.4 KB/s`. This aligns KB/s and MB/s without
    /// trailing whitespace or per-sample status-item resizing.
    private var networkRateNumberWidth: Int {
        switch settings.networkRateDecimalPlaces {
        case 0: return 4       // 1234
        case 1: return 5       // 123.4
        default: return 6      // 123.45
        }
    }

    private func formattedNetworkRate(_ bytesPerSecond: Double) -> FormattedNetworkRate {
        let value: Double
        let unit: String
        switch settings.networkRateUnit {
        case .automatic:
            if bytesPerSecond >= 1_000_000 {
                value = bytesPerSecond / 1_000_000
                unit = "MB/s"
            } else {
                value = bytesPerSecond / 1_000
                unit = "KB/s"
            }
        case .kilobytes:
            value = bytesPerSecond / 1_000
            unit = "KB/s"
        case .megabytes:
            value = bytesPerSecond / 1_000_000
            unit = "MB/s"
        case .megabits:
            value = bytesPerSecond * 8 / 1_000_000
            unit = "Mbps"
        }

        var decimalPlaces = settings.networkRateDecimalPlaces
        var number = formattedNetworkNumber(value, decimalPlaces: decimalPlaces)
        // Prefer the requested precision, but reduce it for unusually high
        // rates before widening the status item.
        while number.count > networkRateNumberWidth, decimalPlaces > 0 {
            decimalPlaces -= 1
            number = formattedNetworkNumber(value, decimalPlaces: decimalPlaces)
        }
        return FormattedNetworkRate(
            number: rightAligned(number, width: networkRateNumberWidth),
            unit: unit
        )
    }

    private func formattedNetworkNumber(_ value: Double, decimalPlaces: Int) -> String {
        String(
            format: "%.\(decimalPlaces)f",
            locale: Locale.autoupdatingCurrent,
            value
        )
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
                    firstLine: settings.showCPU
                        ? resourceUsageText(label: "CPU", value: line.cpu, usage: store.cpu, width: 5, attributes: attributes)
                        : nil,
                    secondLine: settings.showMemory
                        ? resourceUsageText(label: "MEM", value: line.memory, usage: store.memory, width: 5, attributes: attributes)
                        : nil
                )
            case .stacked:
                let metrics = [
                    settings.showCPU ? (label: "CPU", value: line.cpu, usage: store.cpu) : nil,
                    settings.showMemory ? (label: "MEM", value: line.memory, usage: store.memory) : nil
                ].compactMap { $0 }
                let labels = metrics.map { statusBarText($0.label, attributes: attributes) }
                let values = metrics.map {
                    statusBarText(
                        $0.value,
                        attributes: statusBarUsageAttributes(usage: $0.usage, base: attributes)
                    )
                }
                let widths = zip(labels, values).map { max($0.string.count, $1.string.count) }
                return StatusBarGroupContent(
                    firstLine: labels.isEmpty ? nil : joinStatusBarColumns(labels, widths: widths, attributes: attributes, separator: "  "),
                    secondLine: values.isEmpty ? nil : joinStatusBarColumns(values, widths: widths, attributes: attributes, separator: "  ")
                )
            }

        case .network:
            let upload = formattedNetworkRate(line.upload)
            let download = formattedNetworkRate(line.download)
            let uploadPrefix = settings.showStatusBarMetricIcons ? "↑ " : ""
            let downloadPrefix = settings.showStatusBarMetricIcons ? "↓ " : ""
            return StatusBarGroupContent(
                firstLine: settings.showUpload ? statusBarText("\(uploadPrefix)\(upload.number) \(upload.unit)", attributes: attributes) : nil,
                secondLine: settings.showDownload ? statusBarText("\(downloadPrefix)\(download.number) \(download.unit)", attributes: attributes) : nil
            )

        case .logo:
            // The runner is provided through the status button's native image
            // property; it is not part of the title text.
            return StatusBarGroupContent(firstLine: nil, secondLine: nil)

        case .typing:
            guard settings.showTypingStatusItem,
                  settings.typingStatsEnabled,
                  typingStats.permissionStatus == .monitoring else {
                return StatusBarGroupContent(firstLine: nil, secondLine: nil)
            }
            return StatusBarGroupContent(
                firstLine: statusBarText(StatsL10n.text("status_bar.typing.label"), attributes: attributes),
                secondLine: statusBarText(
                    compactTypingCount(typingStats.todayKeyCount),
                    attributes: attributes
                )
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
                let color = value.isStale ? NSColor.systemOrange : resourceUsageColor(usage: value.usedPercent)
                return statusBarText(
                    "\(displayed)%",
                    attributes: statusBarUsageAttributes(color: color, base: attributes)
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
            return Array(values.prefix(settings.codexStatusBarAccountLimit))
        }
    }

    private func resourceUsageText(
        label: String,
        value: String,
        usage: Double,
        width: Int,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: label, attributes: attributes)
        result.append(
            NSAttributedString(
                string: rightAligned(value, width: width),
                attributes: statusBarUsageAttributes(usage: usage, base: attributes)
            )
        )
        return result
    }

    private func statusBarUsageAttributes(
        usage: Double,
        base attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        statusBarUsageAttributes(color: resourceUsageColor(usage: usage), base: attributes)
    }

    private func statusBarUsageAttributes(
        color: NSColor,
        base attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        guard settings.statusBarUsageColorsEnabled else { return attributes }
        return attributes.merging([.foregroundColor: color]) { _, new in new }
    }

    private func resourceUsageColor(usage: Double) -> NSColor {
        let clampedUsage = min(100, max(0, usage))
        let color: NSColor
        if clampedUsage > 80 {
            color = .systemRed
        } else if clampedUsage >= 50 {
            color = .systemOrange
        } else {
            color = .systemGreen
        }
        return color
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

    private func statusBarSeparator(
        _ text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        // Tighten only group gaps by about two points; retain monospaced
        // numeric columns and the alignment of the two status-bar rows.
        let spacingAttributes = attributes.merging([.kern: -1.0]) { _, new in new }
        return NSAttributedString(string: text, attributes: spacingAttributes)
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
                result.append(statusBarSeparator(separator, attributes: attributes))
            }
            let width = widths.indices.contains(index) ? widths[index] : segment.string.count
            result.append(segment)
            let padding = max(0, width - segment.string.count)
            if padding > 0 {
                result.append(
                    NSAttributedString(
                        string: String(repeating: " ", count: padding),
                        attributes: attributes
                    )
                )
            }
        }
        return result
    }

    private func compactTypingCount(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : String(value)
    }

    private func rightAligned(_ value: String, width: Int) -> String {
        let padding = max(0, width - value.count)
        return String(repeating: " ", count: padding) + value
    }

}

/// Let the status button handle clicks even over the animated artwork.
private final class StatusBarRunnerImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
