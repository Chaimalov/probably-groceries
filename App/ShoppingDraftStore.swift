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
                              note: previous?.note, photoData: previous?.photoData, section: previous?.sectionName,
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
    @discardableResult
    func confirmDraft(_ draft: ShoppingDraft) -> Bool {
        guard draft.listID == selectedListID else { return false }
        let scope = Set(data.products.filter { productBelongsToCurrentScope($0) }.map(\.id))
        let updated = draft.applying(to: data, productScope: scope)
        guard applyDraftData(updated) else { return false }
        UserDefaults.standard.removeObject(forKey: draftKey(draft.listID))
        return true
    }
}
