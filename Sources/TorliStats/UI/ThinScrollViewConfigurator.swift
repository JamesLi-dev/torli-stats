import AppKit
import SwiftUI

struct ThinScrollViewConfigurator: NSViewRepresentable {
    var verticalInset: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        ScrollViewConfiguratorView(verticalInset: verticalInset)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

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
            configureScrollView()
        }

        private func configureScrollView() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }
                scrollView.scrollerStyle = .overlay
                scrollView.scrollerInsets = NSEdgeInsets(top: self.verticalInset, left: 0, bottom: self.verticalInset, right: 0)
                scrollView.scrollerKnobStyle = .dark
                scrollView.autohidesScrollers = true
                scrollView.hasHorizontalScroller = false
                scrollView.verticalScroller?.controlSize = .mini
                scrollView.verticalScroller?.alphaValue = 0.82
            }
        }
    }
}
