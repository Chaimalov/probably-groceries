import AppIntents
import Foundation

// Opening the host app is intentional: the canonical store owns the CloudKit
// journal and purchase semantics. The widget never edits stale shared snapshots.
struct BuyGroceryIntent: AppIntent {
    static var title: LocalizedStringResource = "סימון כנקנה"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "מוצר")
    var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        guard UUID(uuidString: itemID) != nil else { return .result() }
        UserDefaults(suiteName: GroceryWidgetBridge.suite)?
            .set(itemID, forKey: "pendingWidgetPurchase")
        return .result()
    }
}
