import Foundation
import XCTest

final class GroceryCaptureTests: XCTestCase {
    private let market = ShoppingList(id: UUID(), name: "מכולת", sections: ["מזווה", "שמנים"])
    private let shop = ShoppingList(id: UUID(), name: "מכולת העיר", sections: ["יבשים"])

    func testListResolutionHonorsPermissionsAndDoesNotGuess() {
        let data = ShoppingData(lists: [market, shop])
        var binding = SharedListBinding(listID: market.id, zoneName: "zone", ownerName: "owner", isOwner: false)
        XCTAssertEqual(GroceryCapture.writableLists(in: data, bindings: [binding]).map(\.id), [shop.id])
        binding.canWrite = false
        let readOnly = GroceryCapture.writableLists(in: data, bindings: [binding])
        XCTAssertNil(GroceryCapture.destination(explicit: market.id, preferred: shop.id, writable: readOnly))
        XCTAssertEqual(GroceryCapture.destination(explicit: nil, preferred: market.id, writable: readOnly)?.id, shop.id)
        binding.canWrite = true
        let writable = GroceryCapture.writableLists(in: data, bindings: [binding])
        XCTAssertNil(GroceryCapture.destination(explicit: nil, preferred: nil, writable: writable))
        XCTAssertNil(GroceryCapture.destination(explicit: UUID(), preferred: market.id, writable: writable))
        XCTAssertEqual(GroceryCapture.destination(explicit: nil, preferred: market.id, writable: writable)?.id, market.id)
        XCTAssertEqual(GroceryCapture.lists(matching: " מכולת ", in: writable).map(\.id), [market.id])
        XCTAssertEqual(GroceryCapture.lists(matching: "מכולת", in: [market, market]).count, 2)
        binding.accessible = false
        XCTAssertEqual(GroceryCapture.writableLists(in: data, bindings: [binding]).map(\.id), [shop.id])
    }

    func testParsesConservativeQuantitiesAndPreservesUncertainNames() {
        XCTAssertEqual(ShoppingInputParser.parse("שלוש חבילות פסטה"),
                       .init(name: "פסטה", quantity: 3, unit: "חבילות"))
        XCTAssertEqual(ShoppingInputParser.parse("שמן קנולה 2 ליטר"),
                       .init(name: "שמן קנולה", quantity: 2, unit: "ליטרים"))
        XCTAssertEqual(ShoppingInputParser.parse("two packs whole grain pasta"),
                       .init(name: "whole grain pasta", quantity: 2, unit: "packs"))
        for name in ["חלב 3%", "0 ליטר שמן", "שלושה שמן", "3 חבילות", "קפה 10000 kg"] {
            XCTAssertEqual(ShoppingInputParser.parse(name), .init(name: name, quantity: 1, unit: nil))
        }
    }

    func testOfflineInsertUsesListHistoryBeforeCatalogAndKeepsOneActiveRow() throws {
        let product = Product(id: UUID(), name: "שמן קנולה", usualQuantity: 1)
        var purchase = Purchase(id: UUID(), productID: product.id, quantity: 1, purchasedAt: .now,
                                sourceItemID: UUID(), listID: market.id)
        purchase.sectionName = "שמנים"
        var data = ShoppingData(lists: [market, shop], products: [product], purchases: [purchase])
        let before = data
        let first = try XCTUnwrap(data.insertItem(name: product.name, quantity: 2, category: nil,
            department: nil, urgent: false, listID: market.id, productScope: [product.id], voice: true, unit: "ליטרים"))
        XCTAssertEqual(first.sectionName, "שמנים")
        XCTAssertEqual(first.unit, "ליטרים")

        let inOtherStore = try XCTUnwrap(data.insertItem(name: product.name, quantity: 1, category: nil,
            department: nil, urgent: false, listID: shop.id, productScope: [], voice: true))
        XCTAssertNotEqual(first.productID, inOtherStore.productID)
        XCTAssertEqual(inOtherStore.sectionName, "יבשים")

        let again = try XCTUnwrap(data.insertItem(name: product.name, quantity: 2, category: nil,
            department: nil, urgent: false, listID: market.id, productScope: [product.id], voice: true, unit: "ליטרים"))
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(again.quantity, 4)
        XCTAssertNil(data.insertItem(name: product.name, quantity: 2, category: nil, department: nil,
            urgent: false, listID: market.id, productScope: [product.id], voice: true, unit: "ק״ג"))

        let now = Date.now
        var offline = SyncJournal()
        offline.recordChanges(from: before, to: data, at: now)
        data.voiceReceipts = [.init(key: "request", date: now, fingerprint: "fingerprint", revisions: Array(offline.revisions.values))]
        let reopened = try JSONDecoder().decode(ShoppingData.self, from: JSONEncoder().encode(data))
        var recovered = SyncJournal()
        recovered.recoverVoiceRevisions(in: reopened)
        XCTAssertEqual(recovered.revisions, offline.revisions)
        XCTAssertNotNil(GroceryCapture.receipt(for: "request", in: reopened.voiceReceipts, since: now.addingTimeInterval(-2)))
        XCTAssertNil(GroceryCapture.receipt(for: "request", in: reopened.voiceReceipts, since: now.addingTimeInterval(2)))

        var secondDevice = before
        var secondJournal = SyncJournal()
        for revision in recovered.revisions.values.sorted(by: { $0.key > $1.key }) {
            _ = secondJournal.merge(revision, into: &secondDevice)
        }
        XCTAssertEqual(secondDevice.items.first(where: { $0.id == first.id })?.quantity, 4)
        XCTAssertTrue(secondDevice.voiceReceipts.isEmpty)
    }

    func testLateAliasRefinesOnlyAnUnmovedItemWithinItsList() throws {
        let target = Product(id: UUID(), name: "קנולה", usualQuantity: 1)
        var purchase = Purchase(id: UUID(), productID: target.id, quantity: 1, purchasedAt: .now,
                                sourceItemID: UUID(), listID: market.id)
        purchase.sectionName = "שמנים"
        var data = ShoppingData(lists: [market, shop], products: [target], purchases: [purchase])
        let item = try XCTUnwrap(data.insertItem(name: "קנולה מותג פרטי", quantity: 1, category: nil,
            department: nil, urgent: false, listID: market.id, productScope: [target.id], voice: true))
        let source = try XCTUnwrap(data.products.firstIndex(where: { $0.id == item.productID }))
        XCTAssertEqual(data.sectionName(for: item), "אחר")
        data.products[source].learningLinks = [.init(listID: market.id, targetID: target.id,
            sourceName: data.products[source].name, targetName: target.name, sourceUnit: nil, targetUnit: nil,
            model: "test", policyVersion: "product-identity-v1", probability: 0.99, confidence: 0.95, createdAt: .now)]
        XCTAssertFalse(data.refineVoiceAisle(for: item.productID, listID: shop.id))

        var manuallyMoved = data
        manuallyMoved.items[0].sectionName = ""
        XCTAssertFalse(manuallyMoved.refineVoiceAisle(for: item.productID, listID: market.id))
        XCTAssertEqual(manuallyMoved.items[0].sectionName, "")
        var deleted = data
        deleted.deleteSection(in: market.id, name: "שמנים", includingItems: false)
        XCTAssertFalse(deleted.refineVoiceAisle(for: item.productID, listID: market.id))
        XCTAssertTrue(data.refineVoiceAisle(for: item.productID, listID: market.id))
        XCTAssertEqual(data.items[0].sectionName, "שמנים")
    }
}
