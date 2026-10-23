import Foundation
import XCTest

final class PredictionDiagnosticsTests: XCTestCase {
    func testExportReplaysPredictionsAndOmitsUnrelatedPersonalData() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let product = Product(id: UUID(), name: "חלב", usualQuantity: 2)
        var item = ShoppingItem(id: UUID(), productID: product.id, quantity: 2, addedAt: now)
        item.note = "private-note"
        item.photoData = Data("private-photo".utf8)
        item.photoFilename = "private-path"
        item.shoppingPlace = "private-place"
        let purchases = [21, 14, 7].map { days -> Purchase in
            var purchase = Purchase(id: UUID(), productID: product.id, quantity: 2,
                purchasedAt: now.addingTimeInterval(-Double(days) * 86400), sourceItemID: UUID())
            purchase.actorID = "private-account"
            purchase.note = item.note
            purchase.photoData = item.photoData
            return purchase
        }
        var data = ShoppingData(products: [product], items: [item], purchases: purchases)
        data.watchReceipts = [UUID()]
        data.confirmedDrafts = [UUID()]
        let report = PredictionDiagnostics(data: data, selectedListID: ShoppingList.defaultID, now: now)
        let bytes = try report.encoded()
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        for secret in ["private-note", "private-photo", "private-path", "private-place", "private-account"] {
            XCTAssertFalse(text.contains(secret))
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let replay = try decoder.decode(ShoppingData.self,
            from: JSONSerialization.data(withJSONObject: try XCTUnwrap(root["shoppingData"])))
        XCTAssertEqual(replay.purchases.count, 3)
        XCTAssertNil(replay.items.first?.note)
        XCTAssertNil(replay.items.first?.photoData)
        XCTAssertNil(replay.purchases.first?.actorID)
        XCTAssertNil(replay.purchases.first?.photoData)
        XCTAssertTrue(replay.watchReceipts.isEmpty)
        XCTAssertTrue(replay.confirmedDrafts.isEmpty)
        let evaluated = PredictionEngine.evaluate(replay, now: now)
        XCTAssertEqual(evaluated.first?.reason, report.evaluations.first?.products.first?.reason)
        XCTAssertEqual(evaluated.first?.distinctTripCount, 3)
        XCTAssertEqual(evaluated.first?.reason, "כבר ברשימה")
        XCTAssertEqual(evaluated.first?.intervalDays, 7)
        XCTAssertEqual(report.schemaVersion, 1)
    }

    func testReportIncludesEachListAndEmptySavedDraftWithoutChangingInput() throws {
        let second = ShoppingList(id: UUID(), name: "סופר")
        let product = Product(id: UUID(), name: "לחם", usualQuantity: 1)
        var data = ShoppingData(lists: [ShoppingList(id: ShoppingList.defaultID, name: "קניות"), second],
            products: [product])
        let draft = ShoppingDraft(listID: second.id, entries: [])
        data.confirmedDrafts = [draft.token]
        let report = PredictionDiagnostics(data: data, selectedListID: second.id, drafts: [draft])
        XCTAssertEqual(report.evaluations.count, 2)
        XCTAssertEqual(report.selectedListID, second.id)
        XCTAssertEqual(report.cachedDrafts.first?.listID, second.id)
        XCTAssertEqual(report.cachedDrafts.first?.alreadyConfirmed, true)
        XCTAssertEqual(report.cachedDrafts.first?.entries.count, 0)
        XCTAssertEqual(data.confirmedDrafts, [draft.token])
        XCTAssertEqual(report.evaluations[1].products.first?.reason, "נדרשות שלוש קניות נפרדות")
        XCTAssertNoThrow(try report.encoded())
    }
}
