import SwiftUI
import UIKit

/// Installs the iOS two-finger pan on the List's scroll view without covering row controls.
struct TwoFingerSelectionGesture: UIViewRepresentable {
    var onDrag: (CGPoint, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDrag: onDrag) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onAttach = { [weak coordinator = context.coordinator] anchor in
            coordinator?.install(on: anchor)
        }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.onDrag = onDrag
        context.coordinator.install(on: uiView)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class AnchorView: UIView {
        var onAttach: ((AnchorView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onAttach?(self)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDrag: (CGPoint, CGPoint) -> Void
        private weak var scrollView: UIScrollView?
        private var gesture: UIPanGestureRecognizer?
        private var previousPoint: CGPoint?

        init(onDrag: @escaping (CGPoint, CGPoint) -> Void) {
            self.onDrag = onDrag
        }

        func install(on anchor: AnchorView) {
            guard let window = anchor.window else { return }
            var parent = anchor.superview
            var scroll: UIScrollView?
            while let view = parent {
                if let candidate = view as? UIScrollView {
                    scroll = candidate
                    break
                }
                parent = view.superview
            }
            scroll = scroll ?? findListScrollView(in: window, near: anchor)
            guard let scroll, scroll !== scrollView else { return }
            uninstall()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            scroll.addGestureRecognizer(pan)
            scrollView = scroll
            gesture = pan
        }

        private func findListScrollView(in root: UIView, near anchor: UIView) -> UIScrollView? {
            let origin = anchor.convert(.zero, to: root)
            func search(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UICollectionView,
                   scroll.frame(in: root).contains(origin) { return scroll }
                for child in view.subviews {
                    if let match = search(child) { return match }
                }
                return nil
            }
            return search(root)
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            guard let window = pan.view?.window else { return }
            let point = pan.location(in: window)
            switch pan.state {
            case .began:
                previousPoint = point
                onDrag(point, point)
            case .changed:
                onDrag(previousPoint ?? point, point)
                previousPoint = point
            default:
                previousPoint = nil
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func uninstall() {
            if let gesture { scrollView?.removeGestureRecognizer(gesture) }
            gesture = nil
            scrollView = nil
            previousPoint = nil
        }
    }
}

private extension UIView {
    func frame(in ancestor: UIView) -> CGRect {
        convert(bounds, to: ancestor)
    }
}
