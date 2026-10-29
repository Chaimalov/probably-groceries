import Foundation

enum BadgePolicy {
    static func count(in data: ShoppingData, selectedListID: UUID, defaults: UserDefaults = .standard) -> Int {
        guard defaults.bool(forKey: "shoppingBadgeEnabled") else { return 0 }
        let mode = defaults.string(forKey: "shoppingBadgeLists") ?? "selected"
        let selected = Set((defaults.stringArray(forKey: "shoppingBadgeListIDs") ?? []).compactMap(UUID.init(uuidString:)))
        let validLists = Set(data.lists.map(\.id))
        let items = data.items.filter {
            validLists.contains($0.listID) &&
            (mode == "all" || (mode == "chosen" ? selected.contains($0.listID) : $0.listID == selectedListID)) &&
            (!defaults.bool(forKey: "shoppingBadgeUrgentOnly") || $0.isUrgent) &&
            (!defaults.bool(forKey: "shoppingBadgeExcludeUnavailable") || $0.unavailable != true)
        }
        return defaults.bool(forKey: "shoppingBadgeQuantities")
            ? items.reduce(0) { min(99999, $0 + max(1, min(9999, $1.quantity))) } : items.count
    }
}
