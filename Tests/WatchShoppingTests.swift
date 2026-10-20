import Foundation
import XCTest

final class WatchShoppingTests: XCTestCase {
    func testOfflineBuyThenUndoSurvivesStaleSnapshotAndPartialAcknowledgement() throws {
        let item = UUID(), list = UUID()
        let buy = WatchPurchaseCommand(id: UUID(), itemID: item, listID: list, purchased: true, date: .now)
        let undo = WatchPurchaseCommand(id: UUID(), itemID: item, listID: list, purchased: false, date: .now)
        let row = WatchShoppingSnapshot.Row(id: item, name: "חלב", quantity: 2, unit: "ליטר",
                                           section: "מקרר", note: nil, purchased: false)
        var snapshot = WatchShoppingSnapshot(date: .now, selectedListID: list,
            lists: [.init(id: list, name: "קניות", tint: "green", sections: ["מקרר"], rows: [row])], receipts: [])
        let queue = try JSONDecoder().decode([WatchPurchaseCommand].self, from: JSONEncoder().encode([buy, undo]))
        XCTAssertTrue(snapshot.overlaying([buy]).lists[0].rows[0].purchased)
        XCTAssertFalse(snapshot.overlaying(queue).lists[0].rows[0].purchased)
        snapshot.lists[0].rows[0].purchased = true
        let partial = WatchShoppingSnapshot(date: .now, selectedListID: list, lists: snapshot.lists, receipts: [buy.id])
        XCTAssertFalse(partial.overlaying(queue).lists[0].rows[0].purchased)
        XCTAssertEqual(partial.overlaying(queue).lists[0].rows[0].quantity, 2)
    }

    func testAcknowledgedOldBuyDoesNotOverrideLaterPhoneUndo() {
        let item = UUID(), list = UUID()
        let buy = WatchPurchaseCommand(id: UUID(), itemID: item, listID: list, purchased: true, date: .now)
        let row = WatchShoppingSnapshot.Row(id: item, name: "לחם", quantity: 1, unit: nil,
                                           section: "מאפייה", note: nil, purchased: false)
        let snapshot = WatchShoppingSnapshot(date: .now, selectedListID: list,
            lists: [.init(id: list, name: "קניות", tint: "blue", sections: ["מאפייה"], rows: [row])], receipts: [buy.id])
        XCTAssertFalse(snapshot.overlaying([buy]).lists[0].rows[0].purchased)
    }

    func testOldShoppingFilesDecodeAndWatchReceiptsPersist() throws {
        var data = try JSONDecoder().decode(ShoppingData.self, from: Data("{}".utf8))
        XCTAssertTrue(data.watchReceipts.isEmpty)
        data.watchReceipts = [UUID()]
        let restored = try JSONDecoder().decode(ShoppingData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.watchReceipts, data.watchReceipts)
    }
}
