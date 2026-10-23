import Foundation

struct WatchPurchaseCommand: Codable, Identifiable, Equatable {
    let id: UUID
    let itemID: UUID
    let listID: UUID
    let purchased: Bool
    let date: Date
}

struct WatchShoppingSnapshot: Codable {
    struct Row: Codable, Identifiable {
        let id: UUID
        let name: String
        let quantity: Int
        let unit: String?
        let section: String
        let note: String?
        var purchased: Bool
        // Optional so cached snapshots from older phone builds still decode.
        var isUrgent: Bool? = nil
    }
    struct List: Codable, Identifiable {
        let id: UUID
        let name: String
        let tint: String
        let sections: [String]
        var rows: [Row]
    }
    let date: Date
    let selectedListID: UUID
    var lists: [List]
    let receipts: [UUID]

    /// Pending intent wins over a snapshot that predates delivery to the phone.
    func overlaying(_ commands: [WatchPurchaseCommand]) -> Self {
        var result = self
        for command in commands where !receipts.contains(command.id) {
            guard let list = result.lists.firstIndex(where: { $0.id == command.listID }),
                  let row = result.lists[list].rows.firstIndex(where: { $0.id == command.itemID }) else { continue }
            result.lists[list].rows[row].purchased = command.purchased
        }
        return result
    }
}

enum WatchShoppingWire {
    static let snapshot = "shoppingSnapshotV1"
    static let commands = "shoppingCommandsV1"
    static let refresh = "refreshShoppingV1"
}

