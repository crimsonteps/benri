import AppKit
import SwiftUI

struct ScrollIndicatorHider: NSViewRepresentable {
    let updateToken: Int

    init(updateToken: Int = 0) {
        self.updateToken = updateToken
    }

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.scheduleUpdate()
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdate()
        }

        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in
                self?.hideNearestScrollIndicators()
            }
        }

        private func hideNearestScrollIndicators() {
            guard let contentView = window?.contentView else { return }

            let centerInWindow = convert(
                NSPoint(x: bounds.midX, y: bounds.midY),
                to: nil
            )
            let scrollView = scrollViews(in: contentView)
                .filter { scrollView in
                    !scrollView.isHidden
                        && scrollView.bounds.contains(
                            scrollView.convert(centerInWindow, from: nil)
                        )
                }
                .min { lhs, rhs in
                    lhs.bounds.width * lhs.bounds.height
                        < rhs.bounds.width * rhs.bounds.height
                }

            scrollView?.hasVerticalScroller = false
            scrollView?.hasHorizontalScroller = false
        }

        private func scrollViews(in view: NSView) -> [NSScrollView] {
            var result = view.subviews.compactMap { $0 as? NSScrollView }
            for subview in view.subviews {
                result.append(contentsOf: scrollViews(in: subview))
            }
            return result
        }
    }
}
