import AppKit

/// Keeps the status text and runner in separate views. Updating a status
/// item's `image` causes AppKit to redraw the whole status-item scene; updating
/// this small image subview only invalidates the animated runner.
final class StatusBarLayeredContentView: NSView {
    private let textImageView = NSImageView()
    private let runnerImageView = NSImageView()
    private var textImage: NSImage?
    private var runnerOriginX: CGFloat = 0
    private var runnerSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textImageView.imageScaling = .scaleNone
        runnerImageView.imageScaling = .scaleNone
        runnerImageView.contentTintColor = .labelColor
        addSubview(textImageView)
        addSubview(runnerImageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(textImage: NSImage, runnerOriginX: CGFloat, runnerImage: NSImage?) {
        let newRunnerSize = runnerImage?.size ?? runnerSize
        let needsRelayout = self.textImage?.size != textImage.size
            || self.runnerOriginX != runnerOriginX
            || runnerSize != newRunnerSize

        self.textImage = textImage
        self.runnerOriginX = runnerOriginX
        runnerSize = newRunnerSize
        textImageView.image = textImage
        runnerImageView.image = runnerImage
        if needsRelayout { needsLayout = true }
    }

    func updateRunnerImage(_ image: NSImage?) {
        // All runner frames normally have identical dimensions. Re-laying out
        // an NSStatusItem subview every frame makes AppKit refresh the whole
        // status-item scene, so only relayout if an asset's geometry changed.
        let newRunnerSize = image?.size ?? runnerSize
        runnerImageView.image = image
        guard runnerSize != newRunnerSize else { return }
        runnerSize = newRunnerSize
        needsLayout = true
    }

    // Keep the status button responsible for mouse tracking and its action.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let textImage else { return }
        let originY = floor((bounds.height - textImage.size.height) / 2)
        textImageView.frame = NSRect(origin: NSPoint(x: 0, y: originY), size: textImage.size)
        runnerImageView.frame = NSRect(
            x: runnerOriginX,
            y: floor((bounds.height - runnerSize.height) / 2),
            width: runnerSize.width,
            height: runnerSize.height
        )
    }
}
