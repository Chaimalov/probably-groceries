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
    var photoData: Data? = nil
    var section: String? = nil
    var reason: String?
}

struct ShoppingDraft: Codable, Equatable {
    var token = UUID()
    var listID: UUID
    var createdAt = Date.now
    var entries: [DraftEntry]
    var unfinishedName: String? = nil

    // Only additions are stored. Retained requests always come from the live
    // list, so confirmation cannot resurrect a stale purchase or deletion.
    func additions(to data: ShoppingData) -> [DraftEntry] {
        let active = Set(data.items.filter { $0.listID == listID }.map(\.productID))
        let purchasedSinceDraft = Set(data.purchases.filter { $0.listID == listID && $0.purchasedAt >= createdAt }.map(\.productID))
        let removedSinceDraft = Set(data.deferrals.filter { $0.listID == listID && ($0.recordedAt ?? .distantPast) >= createdAt }.map(\.productID))
        return entries.filter {
            $0.included && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.productID.map { !active.contains($0) && !purchasedSinceDraft.contains($0) && !removedSinceDraft.contains($0) } ?? true)
        }
    }
}

extension ShoppingDraft {
    func applying(to current: ShoppingData, productScope: Set<UUID>) -> ShoppingData {
        guard current.lists.contains(where: { $0.id == listID }), !current.confirmedDrafts.contains(token) else { return current }
        var updated = current
        for entry in additions(to: current) {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let productID: UUID
            if let id = entry.productID {
                guard productScope.contains(id), let index = updated.products.firstIndex(where: { $0.id == id }) else { continue }
                productID = id
                // Preserve a newer explicit rename arriving during preparation.
                if updated.products[index].name == entry.originalName,
                   !updated.products.contains(where: { $0.id != id && productScope.contains($0.id) && Self.normalize($0.name) == Self.normalize(name) }) {
                    updated.products[index].name = name
                }
            } else {
                let batchIDs = Set(updated.items.filter { $0.listID == listID }.map(\.productID))
                if let existing = updated.products.first(where: {
                    (productScope.contains($0.id) || batchIDs.contains($0.id)) && Self.normalize($0.name) == Self.normalize(name)
                }) { productID = existing.id }
                else {
                    productID = entry.id
                    updated.products.append(Product(id: productID, name: name, usualQuantity: entry.quantity))
                }
            }
            guard !updated.items.contains(where: { $0.listID == listID && $0.productID == productID }),
                  !updated.deferrals.contains(where: { $0.listID == listID && $0.productID == productID && ($0.recordedAt ?? .distantPast) >= createdAt }),
                  !updated.purchases.contains(where: { $0.listID == listID && $0.productID == productID && $0.purchasedAt >= createdAt }) else { continue }
            var item = ShoppingItem(id: entry.id, productID: productID, quantity: max(1, min(9999, entry.quantity)), addedAt: .now, listID: listID)
            item.note = entry.note
            item.unit = entry.unit
            item.shoppingPlace = entry.place?.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.shoppingPlace == "" { item.shoppingPlace = nil }
            item.photoData = entry.photoData
            item.sectionName = entry.section
            updated.items.append(item)
        }
        updated.confirmedDrafts.append(token)
        return updated
    }
    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum ShoppingInputParser {
    struct Result: Equatable { var name: String; var quantity: Int; var unit: String? }
    static func parse(_ raw: String) -> Result {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: " ").map(String.init)
        let units = ["packs": "packs", "pack": "packs", "liters": "liters", "kg": "kg", "חב": "חבילות", "חבילות": "חבילות", "ליטר": "ליטרים", "ק״ג": "ק״ג", "יחידות": "יחידות"]
        // A number alone can be part of a product name (e.g. milk 3%). Only
        // parse an explicit recognized trailing unit; keep all other text.
        if parts.count >= 3, let unit = units[parts.last!],
           let quantity = Int(parts[parts.count - 2]), (1...9999).contains(quantity) {
            return Result(name: parts.dropLast(2).joined(separator: " "), quantity: quantity, unit: unit)
        }
        return Result(name: text, quantity: 1, unit: nil)
    }
}


