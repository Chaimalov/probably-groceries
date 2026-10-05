import Foundation

// Persist routing independently of live entities: tombstones and offline edits
// must keep going to the owner's shared zone, never to a participant's private DB.
struct SharedListBinding: Codable, Equatable {
    var listID: UUID
    var zoneName: String
    var ownerName: String
    var isOwner: Bool
    var keys: Set<String> = []
    var accessible: Bool = true

    static func zoneName(for listID: UUID) -> String { "List_\(listID.uuidString)" }

    static func listID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix("List_") else { return nil }
        return UUID(uuidString: String(name.dropFirst(5)))
    }

    mutating func includeRecords(in data: ShoppingData) {
        keys.formUnion(Self.keys(in: data, listID: listID))
    }

    static func keys(in data: ShoppingData, listID: UUID) -> Set<String> {
        let items = data.items.filter { $0.listID == listID }
        let purchases = data.purchases.filter { $0.listID == listID }
        let deferrals = data.deferrals.filter { $0.listID == listID }
        let products = Set(items.map(\.productID) + purchases.map(\.productID) + deferrals.map(\.productID))
        var result: Set<String> = ["list_\(listID.uuidString)"]
        result.formUnion(items.map { "item_\($0.id.uuidString)" })
        result.formUnion(purchases.map { "purchase_\($0.id.uuidString)" })
        result.formUnion(deferrals.map { "deferral_\(listID.uuidString)_\($0.productID.uuidString)" })
        result.formUnion(products.map { "product_\($0.uuidString)" })
        return result
    }
}
