import SwiftUI
import UIKit
import ObjectiveC

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
        view.attach = { [weak coordinator = context.coordinator] anchor in coordinator?.attach(to: anchor) }
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Anchor, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
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
            // SwiftUI can finish mounting a representable after its window callback.
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

    final class Coordinator: NSObject {
        var parent: NativeShoppingDrag
        weak var anchor: Anchor?
        fileprivate weak var manager: ShoppingDragManager?
        init(_ parent: NativeShoppingDrag) { self.parent = parent }

        func attach(to anchor: Anchor) {
            guard let window = anchor.window else { detach(); return }
            let current = ShoppingDragManager.shared(on: window)
            if manager !== current {
                detach()
                manager = current
                current.register(self)
            }
            self.anchor = anchor
        }

        func detach() {
            manager?.unregister(self)
            manager = nil
            anchor = nil
        }

        fileprivate func rect(in host: UIView) -> CGRect? {
            let window = (host as? UIWindow) ?? host.window
            guard parent.enabled, let anchor, anchor.window != nil, anchor.window === window,
                  anchor.bounds.width > 0, anchor.bounds.height > 0 else { return nil }
            return anchor.convert(anchor.bounds, to: host)
        }
    }
}

// One public UIKit interaction pair on the screen, with visible row rectangles.
// No dependency on SwiftUI's collection-cell classes, reuse, or hosting hierarchy.
// Controls remain hit-testable: the transparent row anchors never intercept taps.
fileprivate final class ShoppingDragManager: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate {
    private static var key: UInt8 = 0
    private weak var host: UIView?
    private struct WeakRow { weak var value: NativeShoppingDrag.Coordinator? }
    private var rows: [WeakRow] = []
    private let indicator = UIView()
    private var hoverEntry: ShoppingDragEntry?
    private var hoverAfter: Bool?
    private var dropPoint: CGPoint?
    private var loggedHover = false

    private func debug(_ message: String) {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { print("ShoppingDrag: " + message) }
    }

    static func shared(on host: UIView) -> ShoppingDragManager {
        if let existing = objc_getAssociatedObject(host, &key) as? ShoppingDragManager { return existing }
        let manager = ShoppingDragManager(host: host)
        objc_setAssociatedObject(host, &key, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
    }

    private init(host: UIView) {
        super.init()
        self.host = host
        let drag = UIDragInteraction(delegate: self)
        drag.isEnabled = true // UIDragInteraction defaults to disabled on iPhone.
        host.addInteraction(drag)
        host.addInteraction(UIDropInteraction(delegate: self))
        indicator.isUserInteractionEnabled = false
        indicator.isAccessibilityElement = false
        indicator.isHidden = true
        host.addSubview(indicator)
    }

    func register(_ row: NativeShoppingDrag.Coordinator) {
        rows.removeAll { $0.value == nil }
        if !rows.contains(where: { $0.value === row }) { rows.append(WeakRow(value: row)) }
    }

    func unregister(_ row: NativeShoppingDrag.Coordinator) {
        rows.removeAll { $0.value == nil || $0.value === row }
    }

    private func row(at point: CGPoint, listID: UUID? = nil) -> NativeShoppingDrag.Coordinator? {
        guard let host else { return nil }
        // A presented editor/share sheet must not drag the rows underneath it.
        if let window = host as? UIWindow,
           window.rootViewController?.presentedViewController != nil { return nil }
        return rows.compactMap { ref -> (NativeShoppingDrag.Coordinator, CGRect)? in
            guard let row = ref.value, listID == nil || row.parent.listID == listID,
                  let rect = row.rect(in: host), rect.insetBy(dx: 0, dy: -4).contains(point) else { return nil }
            return (row, rect)
        }.min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
    }

    private func makeItem(for row: NativeShoppingDrag.Coordinator) -> UIDragItem {
        let provider = NSItemProvider()
        let bytes = Data(row.parent.entry.representation.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: "com.chaimalov.probablygroceries.reorder",
                                            visibility: .ownProcess) { completion in
            completion(bytes, nil)
            return nil
        }
        let item = UIDragItem(itemProvider: provider)
        item.localObject = row.parent.entry
        return item
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let host else { return [] }
        let point = session.location(in: host)
        debug("begin at \(point); regions: \(rows.compactMap { $0.value?.rect(in: host) })")
        guard let row = row(at: point) else { debug("no source region"); return [] }
        debug("source found")
        loggedHover = false
        session.localContext = ShoppingDragContext(listID: row.parent.listID)
        return [makeItem(for: row)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForAddingTo session: UIDragSession,
                         withTouchAt point: CGPoint) -> [UIDragItem] {
        guard let context = session.localContext as? ShoppingDragContext,
              let row = row(at: point, listID: context.listID), case .item = row.parent.entry,
              session.items.allSatisfy({ if case .item? = $0.localObject as? ShoppingDragEntry { return true }; return false }),
              !session.items.contains(where: { $0.localObject as? ShoppingDragEntry == row.parent.entry }) else { return [] }
        return [makeItem(for: row)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionForAddingItems sessions: [UIDragSession],
                         withTouchAt point: CGPoint) -> UIDragSession? {
        guard let row = row(at: point), case .item = row.parent.entry else { return nil }
        return sessions.first { ($0.localContext as? ShoppingDragContext)?.listID == row.parent.listID }
    }

    func dragInteraction(_ interaction: UIDragInteraction,
                         sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction,
                         sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }

    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
                         session: UIDragSession) -> UITargetedDragPreview? {
        guard let host, let entry = item.localObject as? ShoppingDragEntry,
              let row = rows.compactMap(\.value).first(where: { $0.parent.entry == entry }),
              let rect = row.rect(in: host),
              let snapshot = host.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .secondarySystemGroupedBackground
        parameters.visiblePath = UIBezierPath(roundedRect: snapshot.bounds, cornerRadius: 12)
        return UITargetedDragPreview(view: snapshot, parameters: parameters,
                                    target: UIDragPreviewTarget(container: host, center: CGPoint(x: rect.midX, y: rect.midY)))
    }

    private func entries(in session: UIDropSession) -> ([ShoppingDragEntry], UUID)? {
        guard let context = session.localDragSession?.localContext as? ShoppingDragContext else { return nil }
        let entries = session.items.compactMap { $0.localObject as? ShoppingDragEntry }
        guard !entries.isEmpty, entries.count == session.items.count,
              rows.contains(where: { $0.value?.parent.listID == context.listID && $0.value?.parent.enabled == true }) else { return nil }
        if entries.allSatisfy({ if case .item = $0 { return true }; return false }) { return (entries, context.listID) }
        if entries.count == 1, case .section = entries[0] { return (entries, context.listID) }
        return nil
    }

    private func destination(in session: UIDropSession) -> (NativeShoppingDrag.Coordinator, [ShoppingDragEntry], Bool)? {
        guard let host, let (entries, listID) = entries(in: session),
              let row = row(at: session.location(in: host), listID: listID),
              !entries.contains(row.parent.entry), let rect = row.rect(in: host) else { return nil }
        if case .section = entries[0], case .item = row.parent.entry { return nil }
        return (row, entries, session.location(in: host).y > rect.midY)
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        // Accept the session across the entire screen, even while over its source
        // row; eligibility at each pointer location is checked in sessionDidUpdate.
        let accepted = entries(in: session) != nil
        debug("canHandle: \(accepted)")
        return accepted
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        if !loggedHover { debug("drop update received"); loggedHover = true }
        guard let host, let (row, _, after) = destination(in: session), let rect = row.rect(in: host) else {
            clearIndicator()
            return UIDropProposal(operation: .cancel)
        }
        if hoverEntry != row.parent.entry || hoverAfter != after { UISelectionFeedbackGenerator().selectionChanged() }
        hoverEntry = row.parent.entry
        hoverAfter = after
        dropPoint = session.location(in: host)
        indicator.backgroundColor = row.parent.tint
        indicator.frame = CGRect(x: rect.minX, y: after ? rect.maxY - 2 : rect.minY, width: rect.width, height: 2)
        indicator.layer.cornerRadius = 1
        indicator.isHidden = false
        host.bringSubviewToFront(indicator)
        return UIDropProposal(operation: .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let host, let (row, entries, after) = destination(in: session) else { debug("invalid destination"); return }
        debug("perform drop; after: \(after)")
        dropPoint = session.location(in: host)
        clearIndicator()
        row.parent.drop(entries, after)
    }

    func dropInteraction(_ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
                         withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        guard let host, let dropPoint else { return defaultPreview }
        // The screen remains alive when SwiftUI moves or reuses individual rows.
        return defaultPreview.retargetedPreview(with: UIDragPreviewTarget(container: host, center: dropPoint))
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { clearIndicator() }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) { clearIndicator() }
    func dropInteraction(_ interaction: UIDropInteraction, concludeDrop session: UIDropSession) { dropPoint = nil }

    private func clearIndicator() {
        indicator.isHidden = true
        hoverEntry = nil
        hoverAfter = nil
    }
}
