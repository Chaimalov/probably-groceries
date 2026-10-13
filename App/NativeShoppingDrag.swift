import SwiftUI
import UIKit

enum ShoppingDragEntry: Hashable {
    case item(UUID)
    case section(String)

    var representation: String {
        switch self {
        case .item(let id): return "item:\(id.uuidString)"
        case .section(let name): return "section:\(name)"
        }
    }
}

// Only local, typed sessions from this list are accepted. Plain text from other
// apps, a stale SwiftUI state value, or another list can never reorder data.
private final class ShoppingDragContext {
    let listID: UUID
    init(listID: UUID) { self.listID = listID }
}

struct NativeShoppingDrag: UIViewRepresentable {
    let entry: ShoppingDragEntry
    let listID: UUID
    let enabled: Bool
    let tint: UIColor
    let drop: ([ShoppingDragEntry], Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.attach = { [weak coordinator = context.coordinator] anchor in
            coordinator?.attach(to: anchor)
        }
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.parent = self
        context.coordinator.drag?.isEnabled = enabled
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        view.attach = nil
        coordinator.detach()
    }

    final class Anchor: UIView {
        var attach: ((Anchor) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach?(self)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.attach?(self)
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            attach?(self)
        }
    }

    // SwiftUI owns the list and its cells. Attach public UIKit interactions to
    // the enclosing reusable view without replacing any list delegates, gestures
    // or controls. The transparent anchor never intercepts taps or swipes.
    final class Coordinator: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
        var parent: NativeShoppingDrag
        weak var host: UIView?
        var drag: UIDragInteraction?
        private var dropInteraction: UIDropInteraction?
        private let indicator = UIView()
        private var insertionAfter: Bool?

        init(_ parent: NativeShoppingDrag) { self.parent = parent }

        func attach(to anchor: UIView) {
            guard anchor.window != nil else { detach(); return }
            var ancestor = anchor.superview
            var target: UIView?
            while let view = ancestor {
                if let cell = view as? UICollectionViewCell { target = cell.contentView; break }
                if let cell = view as? UITableViewCell { target = cell.contentView; break }
                if view is UICollectionReusableView || view is UITableViewHeaderFooterView {
                    target = view; break
                }
                ancestor = view.superview
            }
            guard let target, host !== target else { return }
            detach()
            host = target
            let drag = UIDragInteraction(delegate: self)
            drag.isEnabled = parent.enabled
            let drop = UIDropInteraction(delegate: self)
            target.addInteraction(drag)
            target.addInteraction(drop)
            self.drag = drag
            dropInteraction = drop
            indicator.isUserInteractionEnabled = false
            indicator.isAccessibilityElement = false
            indicator.isHidden = true
            target.addSubview(indicator)
        }

        func detach() {
            if let drag { host?.removeInteraction(drag) }
            if let dropInteraction { host?.removeInteraction(dropInteraction) }
            indicator.removeFromSuperview()
            drag = nil
            dropInteraction = nil
            host = nil
            insertionAfter = nil
        }

        private func makeItem() -> UIDragItem {
            let item = UIDragItem(itemProvider: NSItemProvider(object: parent.entry.representation as NSString))
            item.localObject = parent.entry
            return item
        }

        func dragInteraction(_ interaction: UIDragInteraction,
                             itemsForBeginning session: UIDragSession) -> [UIDragItem] {
            guard parent.enabled else { return [] }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") { print("ShoppingDrag: row lift") }
            session.localContext = ShoppingDragContext(listID: parent.listID)
            return [makeItem()]
        }

        func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession,
                             withTouchAt point: CGPoint) -> [UIDragItem] {
            guard parent.enabled,
                  let context = session.localContext as? ShoppingDragContext,
                  context.listID == parent.listID,
                  case .item = parent.entry,
                  session.items.allSatisfy({ if case .item? = $0.localObject as? ShoppingDragEntry { return true }; return false }),
                  !session.items.contains(where: { $0.localObject as? ShoppingDragEntry == parent.entry })
            else { return [] }
            return [makeItem()]
        }

        func dragInteraction(_ interaction: UIDragInteraction,
                             sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

        func dragInteraction(_ interaction: UIDragInteraction, sessionForAddingItems sessions: [UIDragSession],
                             withTouchAt point: CGPoint) -> UIDragSession? {
            guard parent.enabled, case .item = parent.entry else { return nil }
            return sessions.first { ($0.localContext as? ShoppingDragContext)?.listID == parent.listID }
        }

        func dragInteraction(_ interaction: UIDragInteraction,
                             sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }

        func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
                             session: UIDragSession) -> UITargetedDragPreview? {
            guard let host, let window = host.window,
                  let snapshot = host.snapshotView(afterScreenUpdates: false) else { return nil }
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .secondarySystemGroupedBackground
            parameters.visiblePath = UIBezierPath(roundedRect: host.bounds, cornerRadius: 12)
            let rect = host.convert(host.bounds, to: window)
            return UITargetedDragPreview(view: snapshot, parameters: parameters,
                target: UIDragPreviewTarget(container: window, center: CGPoint(x: rect.midX, y: rect.midY)))
        }

        private func entries(in session: UIDropSession) -> [ShoppingDragEntry]? {
            guard parent.enabled,
                  let context = session.localDragSession?.localContext as? ShoppingDragContext,
                  context.listID == parent.listID else { return nil }
            let entries = session.items.compactMap { $0.localObject as? ShoppingDragEntry }
            guard !entries.isEmpty, entries.count == session.items.count,
                  !entries.contains(parent.entry) else { return nil }
            if entries.allSatisfy({ if case .item = $0 { return true }; return false }) { return entries }
            if entries.count == 1, case .section = entries[0], case .section = parent.entry { return entries }
            return nil
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            let accepted = entries(in: session) != nil
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                print("ShoppingDrag: target \(parent.entry), accepted \(accepted)")
            }
            return accepted
        }

        func dropInteraction(_ interaction: UIDropInteraction,
                             sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            guard entries(in: session) != nil, let host else {
                clearIndicator()
                return UIDropProposal(operation: .cancel)
            }
            let after = session.location(in: host).y > host.bounds.midY
            if insertionAfter != after {
                UISelectionFeedbackGenerator().selectionChanged()
                insertionAfter = after
            }
            indicator.backgroundColor = parent.tint
            indicator.frame = CGRect(x: 16, y: after ? host.bounds.height - 2 : 0,
                                     width: max(0, host.bounds.width - 32), height: 2)
            indicator.layer.cornerRadius = 1
            indicator.isHidden = false
            host.bringSubviewToFront(indicator)
            return UIDropProposal(operation: .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            guard let entries = entries(in: session), let host else { return }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") { print("ShoppingDrag: row drop") }
            let after = session.location(in: host).y > host.bounds.midY
            clearIndicator()
            parent.drop(entries, after)
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            clearIndicator()
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            clearIndicator()
        }

        private func clearIndicator() {
            indicator.isHidden = true
            insertionAfter = nil
        }
    }
}
