import XCTest

final class SharedListBindingTests: XCTestCase {
    func testOnlySelectedListsProductsAndEventsEnterShare() {
        let sharedID = UUID(), privateID = UUID()
        let sharedProduct = Product(id: UUID(), name: "חלב", usualQuantity: 1)
        let privateProduct = Product(id: UUID(), name: "פרטי", usualQuantity: 1)
        let sharedItem = ShoppingItem(id: UUID(), productID: sharedProduct.id, quantity: 1,
                                      addedAt: .now, listID: sharedID)
        let privateItem = ShoppingItem(id: UUID(), productID: privateProduct.id, quantity: 1,
                                       addedAt: .now, listID: privateID)
        let data = ShoppingData(lists: [ShoppingList(id: sharedID, name: "ביחד"),
                                        ShoppingList(id: privateID, name: "פרטי")],
                                products: [sharedProduct, privateProduct], items: [sharedItem, privateItem])
        let keys = SharedListBinding.keys(in: data, listID: sharedID)
        XCTAssertTrue(keys.contains("product_\(sharedProduct.id.uuidString)"))
        XCTAssertTrue(keys.contains("item_\(sharedItem.id.uuidString)"))
        XCTAssertFalse(keys.contains("product_\(privateProduct.id.uuidString)"))
        XCTAssertFalse(keys.contains("item_\(privateItem.id.uuidString)"))
        XCTAssertFalse(keys.contains("list_\(privateID.uuidString)"))
    }

    func testDeletedRecordsKeepSharedRoutingAcrossRestart() throws {
        let listID = UUID()
        let item = ShoppingItem(id: UUID(), productID: UUID(), quantity: 1, addedAt: .now, listID: listID)
        var binding = SharedListBinding(listID: listID, zoneName: SharedListBinding.zoneName(for: listID),
                                        ownerName: "owner", isOwner: false)
        binding.includeRecords(in: ShoppingData(items: [item]))
        binding.includeRecords(in: ShoppingData())
        let restored = try JSONDecoder().decode(SharedListBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertTrue(restored.keys.contains("item_\(item.id.uuidString)"))
        XCTAssertFalse(restored.isOwner)
        XCTAssertEqual(restored.ownerName, "owner")
    }

    func testOldJournalStillDecodes() throws {
        let json = Data(#"{"revisions":{},"zoneReady":true}"#.utf8)
        let journal = try JSONDecoder().decode(SyncJournal.self, from: json)
        XCTAssertNil(journal.sharedLists)
        XCTAssertTrue(journal.zoneReady)
    }

    func testConcurrentCheckOffAndUndoConvergeToOnePurchase() {
        let listID = UUID(), productID = UUID(), itemID = UUID()
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let item = ShoppingItem(id: itemID, productID: productID, quantity: 1, addedAt: time, listID: listID)
        let initial = ShoppingData(items: [item])
        let one = Purchase(id: itemID, productID: productID, quantity: 1,
                           purchasedAt: time.addingTimeInterval(10), sourceItemID: itemID, listID: listID)
        var two = one
        two.purchasedAt = time.addingTimeInterval(11)
        var owner = SyncJournal(), participant = SyncJournal()
        owner.seed(initial, at: time); participant.seed(initial, at: time)
        let first = ShoppingData(purchases: [one]), second = ShoppingData(purchases: [two])
        owner.recordChanges(from: initial, to: first, at: one.purchasedAt)
        participant.recordChanges(from: initial, to: second, at: two.purchasedAt)
        var ownerData = first, participantData = second
        for revision in participant.revisions.values { _ = owner.merge(revision, into: &ownerData) }
        for revision in owner.revisions.values { _ = participant.merge(revision, into: &participantData) }
        XCTAssertEqual(ownerData.purchases.count, 1)
        XCTAssertEqual(ownerData.purchases, participantData.purchases)
        participant.recordChanges(from: participantData, to: initial, at: time.addingTimeInterval(20))
        for revision in participant.revisions.values { _ = owner.merge(revision, into: &ownerData) }
        XCTAssertTrue(ownerData.purchases.isEmpty)
        XCTAssertEqual(ownerData.items.map(\.id), [itemID])
    }
}
