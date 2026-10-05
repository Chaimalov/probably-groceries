import Foundation

// One revision per stable entity ID. A nil payload is a tombstone; deleting a
// purchase must not make it reappear when another device comes online later.
struct SyncRevision: Codable, Equatable {
    var key: String
    var modifiedAt: Date
    var payload: Data?
}

struct SyncJournal: Codable {
    var revisions: [String: SyncRevision] = [:]
    var accountRecordName: String?
    var zoneReady = false
    // Optional for decoding journals written before sharing was supported.
    var sharedLists: [SharedListBinding]? = nil

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    static func records(in data: ShoppingData) -> [String: Data] {
        var records: [String: Data] = [:]
        func insert<T: Encodable>(_ value: T, key: String) {
            records[key] = try? encoder.encode(value)
        }
        for list in data.lists { insert(list, key: "list_\(list.id.uuidString)") }
        for product in data.products { insert(product, key: "product_\(product.id.uuidString)") }
        for item in data.items { insert(item, key: "item_\(item.id.uuidString)") }
        for purchase in data.purchases { insert(purchase, key: "purchase_\(purchase.id.uuidString)") }
        for deferral in data.deferrals {
            insert(deferral, key: "deferral_\(deferral.listID.uuidString)_\(deferral.productID.uuidString)")
        }
        return records
    }

    mutating func recordChanges(from old: ShoppingData, to new: ShoppingData, at date: Date = .now) {
        let before = Self.records(in: old)
        let after = Self.records(in: new)
        for key in Set(before.keys).union(after.keys) where before[key] != after[key] {
            revisions[key] = SyncRevision(key: key, modifiedAt: date, payload: after[key])
        }
    }

    // Existing on-device data predates the journal. Give the built-in empty
    // default list a low priority so a second device can import its real list.
    mutating func seed(_ data: ShoppingData, at date: Date = .now) {
        for (key, payload) in Self.records(in: data) where revisions[key] == nil {
            let isBareDefault = key == "list_\(ShoppingList.defaultID.uuidString)"
                && data.lists.first(where: { $0.id == ShoppingList.defaultID })?.sections.isEmpty == true
                && data.lists.first(where: { $0.id == ShoppingList.defaultID })?.name == "קניות"
            revisions[key] = SyncRevision(key: key,
                                          modifiedAt: isBareDefault ? Date(timeIntervalSince1970: 0) : date,
                                          payload: payload)
        }
    }

    // Returns whether the incoming revision changed local data. Equal clocks
    // use the payload bytes to break a tie deterministically across devices.
    mutating func merge(_ incoming: SyncRevision, into data: inout ShoppingData) -> Bool {
        if let current = revisions[incoming.key] {
            guard incoming.modifiedAt > current.modifiedAt ||
                    (incoming.modifiedAt == current.modifiedAt &&
                     (incoming.payload ?? Data()).lexicographicallyPrecedes(current.payload ?? Data()))
            else { return false }
        }
        guard Self.apply(incoming, to: &data) else { return false }
        revisions[incoming.key] = incoming
        return true
    }

    private static func apply(_ revision: SyncRevision, to data: inout ShoppingData) -> Bool {
        let key = revision.key
        func decode<T: Decodable>(_ type: T.Type) -> T? {
            revision.payload.flatMap { try? decoder.decode(type, from: $0) }
        }
        if key.hasPrefix("list_") {
            if let value = decode(ShoppingList.self) {
                data.lists.removeAll { $0.id == value.id }; data.lists.append(value)
            } else if revision.payload == nil {
                data.lists.removeAll { key == "list_\($0.id.uuidString)" }
            } else { return false }
        } else if key.hasPrefix("product_") {
            if let value = decode(Product.self) {
                data.products.removeAll { $0.id == value.id }; data.products.append(value)
            } else if revision.payload == nil {
                data.products.removeAll { key == "product_\($0.id.uuidString)" }
            } else { return false }
        } else if key.hasPrefix("item_") {
            if let value = decode(ShoppingItem.self) {
                data.items.removeAll { $0.id == value.id }; data.items.append(value)
            } else if revision.payload == nil {
                data.items.removeAll { key == "item_\($0.id.uuidString)" }
            } else { return false }
        } else if key.hasPrefix("purchase_") {
            if let value = decode(Purchase.self) {
                data.purchases.removeAll { $0.id == value.id }; data.purchases.append(value)
            } else if revision.payload == nil {
                data.purchases.removeAll { key == "purchase_\($0.id.uuidString)" }
            } else { return false }
        } else if key.hasPrefix("deferral_") {
            if let value = decode(Deferral.self) {
                data.deferrals.removeAll { key == "deferral_\($0.listID.uuidString)_\($0.productID.uuidString)" }
                data.deferrals.append(value)
            } else if revision.payload == nil {
                data.deferrals.removeAll { key == "deferral_\($0.listID.uuidString)_\($0.productID.uuidString)" }
            } else { return false }
        } else { return false }
        return true
    }
}
