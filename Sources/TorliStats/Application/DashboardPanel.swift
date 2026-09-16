import AppKit

/// A borderless replacement for NSPopover so the dashboard owns its surface
/// shape instead of inheriting the system popover arrow and bezel.
final class DashboardPanel: NSPanel {
    private static let statusBarGap: CGFloat = 12
    private(set) var isShown = false

    var dashboardContentSize: NSSize {
        get {
            contentView?.bounds.size ?? frame.size
        }
        set {
            let topEdge = frame.maxY
            setContentSize(newValue)
            guard isVisible else { return }
            setFrameOrigin(NSPoint(x: frame.origin.x, y: topEdge - frame.height))
        }
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        configurePanel()
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: DashboardView.panelWidth, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
    }

    func present(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        guard let hostWindow = view.window,
              let screen = hostWindow.screen ?? NSScreen.main else { return }

        let anchor = hostWindow.convertToScreen(view.convert(rect, to: nil))
        let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let panelSize = frame.size

        var x = anchor.midX - panelSize.width / 2
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)

        var y: CGFloat
        if preferredEdge == .minY {
            // Keep the panel close to the menu bar while leaving a small
            // breathing room below the status item.
            y = anchor.minY - panelSize.height + Self.statusBarGap
            if y < visibleFrame.minY {
                y = anchor.maxY
            }
        } else {
            y = anchor.maxY
            if y + panelSize.height > visibleFrame.maxY {
                y = anchor.minY - panelSize.height
            }
        }
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)

        setFrame(
            NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height),
            display: false
        )
        isShown = true
        orderFront(nil)
    }

    func dismiss() {
        isShown = false
        orderOut(nil)
    }

    private func configurePanel() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.transient, .ignoresCycle]
    }
}
