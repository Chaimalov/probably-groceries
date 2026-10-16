import AppIntents
import Foundation

struct WidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "מעבר ברשימת הקניות"
    static var isDiscoverable: Bool { false }
    @Parameter(title: "רשימה") var listID: String
    @Parameter(title: "גודל") var family: String
    @Parameter(title: "מיקום") var offset: Int
    init() {}
    init(listID: String, family: String, offset: Int) {
        self.listID = listID; self.family = family; self.offset = offset
    }
    func perform() async throws -> some IntentResult {
        guard UUID(uuidString: listID) != nil else { return .result() }
        UserDefaults(suiteName: GroceryWidgetBridge.suite)?.set(max(0, offset),
            forKey: "widgetPage.\(listID).\(family)")
        return .result()
    }
}
