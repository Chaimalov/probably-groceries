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
        // Store the newest request. The app verifies the row still exists.
        defaults.set(request, forKey: "pendingWidgetPurchase")
        return .result()
    }
}
