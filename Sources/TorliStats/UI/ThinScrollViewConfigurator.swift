import AppKit
import SwiftUI

struct ThinScrollViewConfigurator: NSViewRepresentable {
    var verticalInset: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        ScrollViewConfiguratorView(verticalInset: verticalInset)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollViewConfiguratorView)?.scheduleConfiguration()
    }

    private final class ScrollViewConfiguratorView: NSView {
        private let verticalInset: CGFloat

        init(verticalInset: CGFloat) {
            self.verticalInset = verticalInset
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleConfiguration()
        }

        override func layout() {
            super.layout()
            configureScrollView()
        }

        func scheduleConfiguration() {
            configureScrollView()
            // SwiftUI can finish installing or laying out its NSScrollView
            // after this representable enters the hierarchy. Reapply the
            // inset on the following passes so the overlay scroller remains
            // clear of the rounded panel corners.
            for delay in [0.0, 0.05, 0.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.configureScrollView()
                }
            }
        }

        private func configureScrollView() {
            guard let scrollView = enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            let insets = NSEdgeInsets(top: verticalInset, left: 0, bottom: verticalInset, right: 0)
            if scrollView.scrollerInsets.top != insets.top || scrollView.scrollerInsets.bottom != insets.bottom {
                scrollView.scrollerInsets = insets
            }
            scrollView.scrollerKnobStyle = .dark
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScroller?.controlSize = .mini
            scrollView.verticalScroller?.alphaValue = 0.82
        }
    }
}
