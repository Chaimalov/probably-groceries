import AppIntents
import Foundation

// The host app remains the sole writer of the shopping journal and CloudKit data.
// A timestamp prevents a deferred intent from buying a product days later.
struct BuyGroceryIntent: AppIntent {
    static var title: LocalizedStringResource = "סימון כנקנה"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "מוצר")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        guard UUID(uuidString: itemID) != nil,
              let defaults = UserDefaults(suiteName: GroceryWidgetBridge.suite) else {
            return .result()
        }
        let request = ["itemID": itemID, "requestedAt": String(Date().timeIntervalSince1970)]
        // Preserve rapid check-offs instead of overwriting the previous tap.
        var pending = defaults.array(forKey: "pendingWidgetPurchases") as? [[String: String]] ?? []
        pending.removeAll { $0["itemID"] == itemID }
        pending.append(request)
        defaults.set(Array(pending.suffix(50)), forKey: "pendingWidgetPurchases")
        return .result()
    }
}
