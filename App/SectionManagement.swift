import Foundation

extension ShoppingData {
    func sectionName(for item: ShoppingItem) -> String {
        if let explicit = item.sectionName {
            let name = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "אחר" : name
        }
        let product = products.first { $0.id == item.productID }
        let legacy = [product?.department, product?.category].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "אחר"
        return legacySection(legacy, in: item.listID)
    }

    func sectionNames(in listID: UUID) -> [String] {
        let saved = lists.first { $0.id == listID }?.sections ?? []
        let active = items.filter { $0.listID == listID }.map { sectionName(for: $0) }
        let past = purchases.filter { $0.listID == listID }.map { purchase in
            if let explicit = purchase.sectionName { return explicit.isEmpty ? "אחר" : explicit }
            let product = products.first { $0.id == purchase.productID }
            return legacySection(product?.department ?? product?.category ?? "אחר", in: listID)
        }
        var seen = Set<String>()
        return (saved + active + past).filter { !$0.isEmpty && $0 != "אחר" && seen.insert($0).inserted } + ["אחר"]
    }

    @discardableResult
    mutating func editSection(in listID: UUID, oldName: String, name rawName: String,
                              appearance: SectionAppearance) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard oldName != "אחר", !name.isEmpty, name != "אחר",
              let index = lists.firstIndex(where: { $0.id == listID }),
              sectionNames(in: listID).contains(oldName),
              !sectionNames(in: listID).contains(where: {
                  $0 != oldName && $0.localizedCaseInsensitiveCompare(name) == .orderedSame
              }) else { return false }
        let affected = Set(items.filter { $0.listID == listID && sectionName(for: $0) == oldName }.map(\.id))
        // Materialize legacy sections before rename, keeping their route position.
        lists[index].sections = sectionNames(in: listID).filter { $0 != "אחר" }.map { $0 == oldName ? name : $0 }
        for i in items.indices where affected.contains(items[i].id) { items[i].sectionName = name }
        rewritePastSection(in: listID, from: oldName, to: name)
        var styles = lists[index].sectionStyles ?? [:]
        styles.removeValue(forKey: oldName)
        styles[name] = appearance
        lists[index].sectionStyles = styles
        updateLegacySection(in: listID, from: oldName, to: name)
        return true
    }

    mutating func deleteSection(in listID: UUID, name: String, includingItems: Bool) {
        guard name != "אחר", let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        let affected = Set(items.filter { $0.listID == listID && sectionName(for: $0) == name }.map(\.id))
        lists[index].sections = sectionNames(in: listID).filter { $0 != name && $0 != "אחר" }
        lists[index].sectionStyles?.removeValue(forKey: name)
        if includingItems { items.removeAll { affected.contains($0.id) } }
        else { for i in items.indices where affected.contains(items[i].id) { items[i].sectionName = "" } }
        // History is retained, but cannot recreate the deleted aisle or restore it on undo.
        rewritePastSection(in: listID, from: name, to: "")
        updateLegacySection(in: listID, from: name, to: "")
    }

    private func legacySection(_ name: String, in listID: UUID) -> String {
        let mapped = lists.first { $0.id == listID }?.sectionAliases?[name] ?? name
        return mapped.isEmpty ? "אחר" : mapped
    }

    private mutating func updateLegacySection(in listID: UUID, from name: String, to replacement: String) {
        guard let i = lists.firstIndex(where: { $0.id == listID }) else { return }
        var aliases = lists[i].sectionAliases ?? [:]
        for key in Array(aliases.keys) where aliases[key] == name { aliases[key] = replacement }
        aliases.removeValue(forKey: replacement)
        aliases[name] = replacement
        lists[i].sectionAliases = aliases
    }

    private mutating func rewritePastSection(in listID: UUID, from oldName: String, to name: String) {
        for i in purchases.indices where purchases[i].listID == listID {
            let product = products.first { $0.id == purchases[i].productID }
            let existing = purchases[i].sectionName ?? legacySection(product?.department ?? product?.category ?? "אחר", in: listID)
            if existing == oldName { purchases[i].sectionName = name }
        }
    }
}
