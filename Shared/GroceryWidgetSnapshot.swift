import Foundation

struct GroceryWidgetSnapshot: Codable {
    struct Row: Codable, Identifiable {
        let id: UUID
        let name: String
        let quantity: Int
    }
    let listID: UUID
    let title: String
    let tintName: String
    let total: Int
    let rows: [Row]
}

enum GroceryWidgetBridge {
    static let suite = "group.com.chaimalov.probablygroceries"
    static let key = "groceryWidgetSnapshot"

    static func read() -> GroceryWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GroceryWidgetSnapshot.self, from: data)
    }

    static func publish(_ snapshot: GroceryWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suite)?.set(data, forKey: key)
    }
}
