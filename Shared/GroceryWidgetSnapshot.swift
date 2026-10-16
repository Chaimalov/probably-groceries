import Foundation

struct GroceryWidgetSnapshot: Codable {
    struct Row: Codable, Identifiable {
        let id: UUID
        let name: String
        let unit: String?
        let quantity: Int

        init(id: UUID, name: String, quantity: Int, unit: String? = nil) {
            self.id = id; self.name = name; self.quantity = quantity; self.unit = unit
        }
    }
    let listID: UUID
    let title: String
    let tintName: String
    let total: Int
    let rows: [Row]
    var symbolName: String? = nil
}

enum GroceryWidgetBridge {
    static let suite = "group.com.chaimalov.probablygroceries"
    static let key = "groceryWidgetSnapshot"
    static let allKey = "groceryWidgetSnapshots"

    static func read() -> GroceryWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GroceryWidgetSnapshot.self, from: data)
    }

    static func readAll() -> [GroceryWidgetSnapshot] {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: allKey) else {
            return read().map { [$0] } ?? []
        }
        return (try? JSONDecoder().decode([GroceryWidgetSnapshot].self, from: data)) ?? []
    }

    static func publishAll(_ snapshots: [GroceryWidgetSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults(suiteName: suite)?.set(data, forKey: allKey)
    }

    static func publish(_ snapshot: GroceryWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suite)?.set(data, forKey: key)
    }
}
