import Foundation

extension ShoppingStore {
    private func draftKey(_ listID: UUID) -> String { "shoppingDraft.\(listID.uuidString)" }
    // Inspect existing drafts without creating, refreshing or confirming one.
    func predictionDiagnostics() -> PredictionDiagnostics {
        let drafts = data.lists.compactMap { list -> ShoppingDraft? in
            guard let bytes = UserDefaults.standard.data(forKey: draftKey(list.id)),
                  let draft = try? JSONDecoder().decode(ShoppingDraft.self, from: bytes),
                  draft.listID == list.id else { return nil }
            return draft
        }
        return PredictionDiagnostics(data: data, selectedListID: selectedListID, drafts: drafts,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            storageError: storageError)
    }

    func shoppingDraft() -> ShoppingDraft {
        if let bytes = UserDefaults.standard.data(forKey: draftKey(selectedListID)),
           let draft = try? JSONDecoder().decode(ShoppingDraft.self, from: bytes), draft.listID == selectedListID,
           storageError != nil || !data.confirmedDrafts.contains(draft.token) {
            return draft
        }
        let draft = ShoppingDraft(listID: selectedListID, entries: suggestions.map { suggestion in
            let previous = purchases.first { $0.productID == suggestion.id }
            return DraftEntry(productID: suggestion.id, originalName: suggestion.product.name, name: suggestion.product.name,
                              quantity: suggestion.quantity, unit: suggestion.product.preferredUnit,
                              place: previous?.shoppingPlace,
                              note: previous?.note, photoData: previous?.photoData, section: previous?.sectionName,
                              reason: currentList.decisionRecommendations == true
                                ? "הצעה לפי הקניות האחרונות"
                                : predictionEvaluations.first { $0.id == suggestion.id }?.reason,
                              isDecisionSuggestion: currentList.decisionRecommendations == true ? true : nil)
        })
        saveDraft(draft)
        return draft
    }
    func saveDraft(_ draft: ShoppingDraft) {
        // SwiftUI may deliver its final onChange after confirmation closes the
        // sheet. Do not recreate a completed draft from that callback. Keep it
        // only when the local save failed and confirmation still needs retry.
        if storageError == nil && data.confirmedDrafts.contains(draft.token) {
            UserDefaults.standard.removeObject(forKey: draftKey(draft.listID))
            return
        }
        if let bytes = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(bytes, forKey: draftKey(draft.listID))
        }
    }
    @discardableResult
    func confirmDraft(_ draft: ShoppingDraft) -> Bool {
        guard draft.listID == selectedListID else { return false }
        let scope = Set(data.products.filter { productBelongsToCurrentScope($0) }.map(\.id))
        var applicable = draft
        let validSuggestions = Set(suggestions.map(\.id))
        applicable.entries.removeAll { $0.isDecisionSuggestion == true &&
            ($0.productID.map { !validSuggestions.contains($0) } ?? true) }
        let updated = applicable.applying(to: data, productScope: scope)
        guard applyDraftData(updated) else { return false }
        UserDefaults.standard.removeObject(forKey: draftKey(draft.listID))
        return true
    }
}
