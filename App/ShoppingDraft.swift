import Foundation

struct DraftEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var productID: UUID?
    var originalName: String? = nil
    var name: String
    var quantity: Int
    var unit: String?
    var place: String?
    var included = true
    var note: String? = nil
    var reason: String?
}

struct ShoppingDraft: Codable, Equatable {
    var token = UUID()
    var listID: UUID
    var createdAt = Date.now
    var entries: [DraftEntry]

    // Only additions are stored. Retained requests always come from the live
    // list, so confirmation cannot resurrect a stale purchase or deletion.
    func additions(to data: ShoppingData) -> [DraftEntry] {
        let active = Set(data.items.filter { $0.listID == listID }.map(\.productID))
        let purchasedSinceDraft = Set(data.purchases.filter { $0.listID == listID && $0.purchasedAt >= createdAt }.map(\.productID))
        return entries.filter {
            $0.included && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.productID.map { !active.contains($0) && !purchasedSinceDraft.contains($0) } ?? true)
        }
    }
}

enum ShoppingInputParser {
    struct Result: Equatable { var name: String; var quantity: Int; var unit: String? }
    static func parse(_ raw: String) -> Result {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: " ").map(String.init)
        let units = ["חב": "חבילות", "חבילות": "חבילות", "ליטר": "ליטרים", "ק״ג": "ק״ג", "יחידות": "יחידות"]
        // A number alone can be part of a product name (e.g. milk 3%). Only
        // parse an explicit recognized trailing unit; keep all other text.
        if parts.count >= 3, let unit = units[parts.last!],
           let quantity = Int(parts[parts.count - 2]), (1...9999).contains(quantity) {
            return Result(name: parts.dropLast(2).joined(separator: " "), quantity: quantity, unit: unit)
        }
        return Result(name: text, quantity: 1, unit: nil)
    }
}


