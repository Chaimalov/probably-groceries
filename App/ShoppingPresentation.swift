import Foundation

// Window-local presentation only: the persisted item/purchase loop, widget and
// Watch continue to see real pending items. Never turn a visual placeholder
// back into a purchase or persist a second shopping state.
struct ShoppingPresentation {
    private var order: [UUID] = []
    private var completed: [UUID: ShoppingItem] = [:]

    mutating func retain(_ item: ShoppingItem, among rows: [ShoppingItem]) {
        order = rows.map(\.id)
        completed[item.id] = item
    }

    func rows(active: [ShoppingItem], purchases: [Purchase], listID: UUID) -> [ShoppingItem] {
        let purchased = Set(purchases.filter { $0.listID == listID }.map(\.sourceItemID))
        let active = active.filter { $0.listID == listID }
        var byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        for (id, row) in completed where row.listID == listID && purchased.contains(id) && byID[id] == nil {
            byID[id] = row
        }
        let known = Set(order)
        return order.compactMap { byID[$0] } + active.filter { !known.contains($0.id) }
    }

    mutating func reset() { order = []; completed = [:] }
}
