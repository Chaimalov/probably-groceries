import Foundation

extension ShoppingStore {
    private func draftKey(_ listID: UUID) -> String { "shoppingDraft.\(listID.uuidString)" }
    func shoppingDraft() -> ShoppingDraft {
        if let bytes = UserDefaults.standard.data(forKey: draftKey(selectedListID)),
           let draft = try? JSONDecoder().decode(ShoppingDraft.self, from: bytes), draft.listID == selectedListID {
            return draft
        }
        let draft = ShoppingDraft(listID: selectedListID, entries: suggestions.map { suggestion in
            let previous = purchases.first { $0.productID == suggestion.id }
            return DraftEntry(productID: suggestion.id, originalName: suggestion.product.name, name: suggestion.product.name,
                              quantity: suggestion.quantity, unit: suggestion.product.preferredUnit,
                              place: previous?.shoppingPlace,
                              reason: predictionEvaluations.first { $0.id == suggestion.id }?.reason)
        })
        saveDraft(draft)
        return draft
    }
    func saveDraft(_ draft: ShoppingDraft) {
        if let bytes = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(bytes, forKey: draftKey(draft.listID))
        }
    }
    func confirmDraft(_ draft: ShoppingDraft) {
        guard draft.listID == selectedListID, data.lists.contains(where: { $0.id == draft.listID }) else { return }
        let confirmedKey = "confirmedDraft.\(draft.token.uuidString)"
        guard !UserDefaults.standard.bool(forKey: confirmedKey) else { return }
        var updated = data
        for entry in draft.additions(to: updated) {
            let productID: UUID
            if let id = entry.productID {
                guard updated.products.contains(where: { $0.id == id }) else { continue }
                productID = id
                if let index = updated.products.firstIndex(where: { $0.id == id }),
                   updated.products[index].name == entry.originalName {
                    updated.products[index].name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                let normalized = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeIDs = Set(updated.items.filter { $0.listID == draft.listID }.map(\.productID) + purchases.map(\.productID) + suggestions.map(\.id))
                if let existing = updated.products.first(where: {
                    scopeIDs.contains($0.id) && $0.name.localizedCaseInsensitiveCompare(normalized) == .orderedSame
                }) { productID = existing.id }
                else {
                    productID = entry.id
                    updated.products.append(Product(id: productID, name: normalized, usualQuantity: entry.quantity))
                }
            }
            guard !updated.items.contains(where: { $0.listID == draft.listID && $0.productID == productID }) else { continue }
            var item = ShoppingItem(id: entry.id, productID: productID, quantity: max(1, min(9999, entry.quantity)),
                                    addedAt: .now, listID: draft.listID)
            item.note = entry.note
            item.unit = entry.unit
            item.shoppingPlace = entry.place?.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.items.append(item)
        }
        applyDraftData(updated)
        UserDefaults.standard.set(true, forKey: confirmedKey)
        UserDefaults.standard.removeObject(forKey: draftKey(draft.listID))
    }
}
