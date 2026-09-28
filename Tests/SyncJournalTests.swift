import XCTest

final class SyncJournalTests: XCTestCase {
    func testOfflinePurchaseAndUndoConvergeWithoutResurrectingPurchase() throws {
        let product = Product(id: UUID(), name: "חלב", usualQuantity: 1)
        let item = ShoppingItem(id: UUID(), productID: product.id, quantity: 1, addedAt: .now)
        let initial = ShoppingData(products: [product], items: [item])
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var owner = SyncJournal()
        owner.seed(initial, at: start)
        var other = SyncJournal()
        var otherData = ShoppingData()
        for revision in owner.revisions.values { _ = other.merge(revision, into: &otherData) }
        XCTAssertEqual(otherData.items.map(\.id), [item.id])

        let purchase = Purchase(id: UUID(), productID: product.id, quantity: 1,
                                purchasedAt: start.addingTimeInterval(10), sourceItemID: item.id)
        let purchased = ShoppingData(products: [product], purchases: [purchase])
        owner.recordChanges(from: initial, to: purchased, at: start.addingTimeInterval(10))
        for revision in owner.revisions.values { _ = other.merge(revision, into: &otherData) }
        XCTAssertTrue(otherData.items.isEmpty)
        XCTAssertEqual(otherData.purchases.map(\.id), [purchase.id])

        let restored = ShoppingData(products: [product], items: [item])
        owner.recordChanges(from: purchased, to: restored, at: start.addingTimeInterval(20))
        for revision in owner.revisions.values { _ = other.merge(revision, into: &otherData) }
        // An old device retries the purchase after the undo has already synced.
        let stalePurchase = SyncRevision(key: "purchase_\(purchase.id.uuidString)",
                                         modifiedAt: start.addingTimeInterval(10),
                                         payload: try JSONEncoder().encode(purchase))
        _ = other.merge(stalePurchase, into: &otherData)
        XCTAssertTrue(otherData.purchases.isEmpty)
        XCTAssertEqual(otherData.items.map(\.id), [item.id])
    }

    func testIndependentOfflineAddsRemainSeparate() {
        let one = ShoppingItem(id: UUID(), productID: UUID(), quantity: 1, addedAt: .now)
        let two = ShoppingItem(id: UUID(), productID: UUID(), quantity: 2, addedAt: .now)
        var first = SyncJournal()
        var second = SyncJournal()
        first.recordChanges(from: ShoppingData(), to: ShoppingData(items: [one]))
        second.recordChanges(from: ShoppingData(), to: ShoppingData(items: [two]))
        var firstData = ShoppingData(items: [one])
        var secondData = ShoppingData(items: [two])
        for revision in second.revisions.values { _ = first.merge(revision, into: &firstData) }
        for revision in first.revisions.values { _ = second.merge(revision, into: &secondData) }
        XCTAssertEqual(Set(firstData.items.map(\.id)), Set([one.id, two.id]))
        XCTAssertEqual(Set(secondData.items.map(\.id)), Set([one.id, two.id]))
    }
}
