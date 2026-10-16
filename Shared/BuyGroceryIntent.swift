import AppIntents
import Foundation

// One authoritative store in the host process, even when the app is suspended.
// Never queue a purchase for a future foreground launch or write the journal
// from a second process. WidgetKit reloads after perform() returns.
struct BuyGroceryIntent: AppIntent {
    static var title: LocalizedStringResource = "סימון כנקנה"
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "מוצר") var itemID: String
    @Parameter(title: "רשימה") var listID: String

    init() {}
    init(itemID: String, listID: String) { self.itemID = itemID; self.listID = listID }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        guard let id = UUID(uuidString: itemID), let list = UUID(uuidString: listID) else {
            throw WidgetPurchaseError.invalidItem
        }
        let store = ShoppingStore.shared
        guard store.storageError == nil else { throw WidgetPurchaseError.saveFailed }
        // Stale snapshots and repeated taps must never create duplicate purchases.
        if let item = store.data.items.first(where: { $0.id == id && $0.listID == list }) {
            store.buy(item)
        }
        if store.storageError != nil { throw WidgetPurchaseError.saveFailed }
        // Persist before returning; the existing journal retries offline sync.
        await store.cloudSync.synchronize()
        #else
        // The metadata restricts execution to .main. Fail safely if misrouted.
        throw WidgetPurchaseError.hostRequired
        #endif
        return .result()
    }
}

enum WidgetPurchaseError: LocalizedError {
    case invalidItem, saveFailed, hostRequired
    var errorDescription: String? {
        switch self {
        case .invalidItem: "המוצר אינו זמין ברשימה."
        case .saveFailed: "לא ניתן לשמור את הסימון. פתחו את האפליקציה ונסו שוב."
        case .hostRequired: "יש לפתוח את אפליקציית קניות ולנסות שוב."
        }
    }
}
