import Foundation

enum GroceryCapture {
    static let defaultListKey = "voiceDefaultShoppingListID"

    struct Receipt: Codable {
        let key: String
        let date: Date
        let fingerprint: String
        let revisions: [SyncRevision]
    }

    static func writableLists(in data: ShoppingData, bindings: [SharedListBinding]) -> [ShoppingList] {
        data.lists.filter { list in
            guard let binding = bindings.first(where: { $0.listID == list.id }) else { return true }
            return binding.accessible && (binding.isOwner || binding.canWrite == true)
        }
    }

    static func destination(explicit: UUID?, preferred: UUID?, writable: [ShoppingList]) -> ShoppingList? {
        if let explicit { return writable.first { $0.id == explicit } }
        return writable.first { $0.id == preferred } ?? (writable.count == 1 ? writable.first : nil)
    }

    static func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "he_IL"))
    }

    static func learnedSection(for productID: UUID, in data: ShoppingData, listID: UUID,
                               aliasesOnly: Bool = false) -> String? {
        let sections = Set(data.sectionNames(in: listID))
        let group = ProductLearning.groups(in: data, listID: listID)[productID] ?? []
        let exact = aliasesOnly ? [] : [productID]
        for ids in [Set(exact), group.subtracting([productID])] where !ids.isEmpty {
            let history = data.purchases.filter { $0.listID == listID && ids.contains($0.productID) }
                .sorted { ($0.purchasedAt, $0.id.uuidString) > ($1.purchasedAt, $1.id.uuidString) }
            if let section = history.lazy.compactMap(\.sectionName).first(where: { $0.isEmpty || sections.contains($0) }) {
                if !section.isEmpty && section != "אחר" { return section }
                if !aliasesOnly && ids.contains(productID) { return "אחר" }
            }
            if let section = data.items.lazy
                .filter({ $0.listID == listID && ids.contains($0.productID) })
                .compactMap(\.sectionName).first(where: { sections.contains($0) && $0 != "אחר" }) {
                return section
            }
        }
        return nil
    }

    static func lists(matching query: String, in lists: [ShoppingList]) -> [ShoppingList] {
        let name = normalize(query)
        guard !name.isEmpty else { return [] }
        let exact = lists.filter { normalize($0.name) == name }
        return exact.isEmpty ? lists.filter { normalize($0.name).contains(name) } : exact
    }

    static func catalogSection(for name: String, in sections: [String]) -> String? {
        let normalized = normalize(name)
        let rules: [([String], [String])] = [
            (["שמן", "פסטה", "אורז", "קמח", "oil", "pasta", "rice", "flour"],
             ["מזווה", "יבשים", "מוצרים יבשים", "pantry", "dry goods"]),
            (["חלב", "גבינה", "יוגורט", "milk", "cheese", "yogurt"],
             ["חלב", "מוצרי חלב", "מקרר", "dairy"]),
            (["לחם", "חלה", "פיתה", "bread", "pita"],
             ["לחם", "מאפייה", "מאפיה", "bakery"]),
            (["מלפפון", "עגבנייה", "עגבניה", "בננה", "cucumber", "tomato", "banana"],
             ["ירקות ופירות", "פירות וירקות", "produce"])
        ]
        guard let rule = rules.first(where: { rule in
            rule.0.contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
        }) else { return nil }
        // A catalog hit is safe only when the store has one matching aisle.
        let matches = sections.filter { rule.1.contains(normalize($0)) }
        return matches.count == 1 ? matches[0] : nil
    }

    static func receipt(for key: String, in receipts: [Receipt], since cutoff: Date) -> Receipt? {
        receipts.last { $0.key == key && $0.date >= cutoff }
    }
}

extension ShoppingData {
    @discardableResult
    mutating func refineVoiceAisle(for productID: UUID, listID: UUID) -> Bool {
        guard let aisle = GroceryCapture.learnedSection(for: productID, in: self, listID: listID, aliasesOnly: true),
              let index = items.firstIndex(where: {
                  $0.listID == listID && $0.productID == productID && $0.needsVoiceAisle == true &&
                  $0.sectionName == nil
              }) else { return false }
        items[index].sectionName = aisle
        items[index].needsVoiceAisle = nil
        return true
    }

    mutating func insertItem(name: String, quantity: Int, category: String?, department: String?, urgent: Bool,
                            listID: UUID, productScope: Set<UUID>, voice: Bool = false, unit: String? = nil) -> ShoppingItem? {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return nil }
        let normalized = GroceryCapture.normalize(displayName)
        let productID: UUID
        if let existing = products.first(where: {
            GroceryCapture.normalize($0.name) == normalized &&
            productScope.contains($0.id)
        }) {
            productID = existing.id
            if let category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let index = products.firstIndex(where: { $0.id == productID }) {
                products[index].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            let product = Product(id: UUID(), name: displayName, usualQuantity: max(1, quantity),
                                  category: category?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  department: nil)
            products.append(product)
            productID = product.id
        }
        if let index = items.firstIndex(where: {
            $0.productID == productID && $0.listID == listID
        }) {
            if voice, let unit, unit != items[index].unit { return nil }
            if voice, items[index].quantity > 9999 - quantity { return nil }
            items[index].quantity += max(1, quantity)
            items[index].isUrgent = items[index].isUrgent || urgent
            if let department { items[index].sectionName = department.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            items.append(ShoppingItem(id: UUID(), productID: productID,
                                           quantity: max(1, quantity), addedAt: .now,
                                           listID: listID, isUrgent: urgent))
            items[items.count - 1].unit = products.first(where: { $0.id == productID })?.preferredUnit
            let index = items.count - 1
            if voice {
                items[index].sectionName = GroceryCapture.learnedSection(for: productID, in: self, listID: listID)
                    ?? GroceryCapture.catalogSection(for: displayName, in: sectionNames(in: listID))
                items[index].needsVoiceAisle = items[index].sectionName == nil ? true : nil
            } else {
                items[index].sectionName = department?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? purchases.filter { $0.productID == productID && $0.listID == listID }
                        .max(by: { $0.purchasedAt < $1.purchasedAt })?.sectionName
            }
        }
        deferrals.removeAll { $0.productID == productID && $0.listID == listID }
        guard let itemIndex = items.firstIndex(where: { $0.productID == productID && $0.listID == listID }) else { return nil }
        if let unit {
            items[itemIndex].unit = unit
            if let index = products.firstIndex(where: { $0.id == productID }) {
                products[index].preferredUnit = unit
            }
        }
        return items[itemIndex]
    }
}
