import XCTest

final class ShoppingDraftTests: XCTestCase {
    func testDraftUsesLatestActiveListAndDoesNotWriteRetainedSnapshots() {
        let id = UUID()
        let entry = DraftEntry(productID: id, name: "חלב", quantity: 2)
        let draft = ShoppingDraft(listID: ShoppingList.defaultID, entries: [entry])
        let item = ShoppingItem(id: UUID(), productID: id, quantity: 5, addedAt: .now)
        XCTAssertTrue(draft.additions(to: ShoppingData(items: [item])).isEmpty)
        XCTAssertEqual(draft.additions(to: ShoppingData()).count, 1)
        XCTAssertEqual(draft.entries[0].quantity, 2)
    }
    func testExclusionAndPersistencePreserveIdentityAndEdits() throws {
        var entry = DraftEntry(name: "לחם", quantity: 3, unit: "חבילות", place: "מוטי")
        entry.included = false
        let draft = ShoppingDraft(listID: UUID(), entries: [entry])
        let restored = try JSONDecoder().decode(ShoppingDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertTrue(restored.additions(to: ShoppingData()).isEmpty)
    }
    func testPurchaseAfterDraftDoesNotReappearOnConfirmation() {
        let id = UUID()
        let draft = ShoppingDraft(listID: ShoppingList.defaultID, entries: [DraftEntry(productID: id, name: "חלב", quantity: 1)])
        let purchase = Purchase(id: UUID(), productID: id, quantity: 1, purchasedAt: draft.createdAt.addingTimeInterval(1), sourceItemID: UUID())
        XCTAssertTrue(draft.additions(to: ShoppingData(purchases: [purchase])).isEmpty)
    }

    func testConfirmationIsIdempotentAfterPersistenceAndPurchase() throws {
        let listID = ShoppingList.defaultID
        let draft = ShoppingDraft(listID: listID, entries: [DraftEntry(name: "חלב", quantity: 2)])
        let first = draft.applying(to: ShoppingData(), productScope: [])
        var restored = try JSONDecoder().decode(ShoppingData.self, from: JSONEncoder().encode(first))
        let item = try XCTUnwrap(restored.items.first)
        restored.items = []
        restored.purchases = [Purchase(id: item.id, productID: item.productID, quantity: item.quantity,
                                      purchasedAt: .now, sourceItemID: item.id)]
        let retried = draft.applying(to: restored, productScope: [item.productID])
        XCTAssertTrue(retried.items.isEmpty)
        XCTAssertEqual(retried.purchases.count, 1)
        XCTAssertEqual(retried.confirmedDrafts, [draft.token])
    }

    func testConfirmationPreservesConcurrentRequestAndDeduplicatesManualEntries() {
        let product = Product(id: UUID(), name: "לחם", usualQuantity: 1)
        let current = ShoppingItem(id: UUID(), productID: product.id, quantity: 7, addedAt: .now)
        let data = ShoppingData(products: [product], items: [current])
        let draft = ShoppingDraft(listID: ShoppingList.defaultID, entries: [
            DraftEntry(name: "לחם", quantity: 2),
            DraftEntry(name: "מלפפון", quantity: 3),
            DraftEntry(name: "  מלפפון  ", quantity: 8)])
        let confirmed = draft.applying(to: data, productScope: [product.id])
        XCTAssertEqual(confirmed.items.count, 2)
        XCTAssertEqual(confirmed.items.first(where: { $0.id == current.id })?.quantity, 7)
        XCTAssertEqual(confirmed.products.count, 2)
        XCTAssertTrue(confirmed.purchases.isEmpty)
    }

    func testHiddenIncludedContextIsConfirmedAndExclusionStaysLocal() {
        var excluded = DraftEntry(name: "אבקה", quantity: 2, place: "מוטי")
        excluded.included = false
        let included = DraftEntry(name: "ספריי", quantity: 1, place: "סופר", note: "הבקבוק הכחול",
                                  photoData: Data([1, 2, 3]), section: "ניקיון")
        let draft = ShoppingDraft(listID: ShoppingList.defaultID, entries: [excluded, included])
        let confirmed = draft.applying(to: ShoppingData(), productScope: [])
        XCTAssertEqual(confirmed.items.count, 1)
        XCTAssertEqual(confirmed.items.first?.shoppingPlace, "סופר")
        XCTAssertEqual(confirmed.items.first?.photoData, included.photoData)
        XCTAssertEqual(confirmed.items.first?.sectionName, "ניקיון")
        XCTAssertTrue(confirmed.deferrals.isEmpty)
    }

    func testConcurrentRenameWinsOverProposalRename() {
        let product = Product(id: UUID(), name: "חלב סויה", usualQuantity: 1)
        let draft = ShoppingDraft(listID: ShoppingList.defaultID, entries: [
            DraftEntry(productID: product.id, originalName: "חלב", name: "חלב שקדים", quantity: 1)])
        let confirmed = draft.applying(to: ShoppingData(products: [product]), productScope: [product.id])
        XCTAssertEqual(confirmed.products.first?.name, "חלב סויה")
        XCTAssertEqual(confirmed.items.first?.productID, product.id)
    }

    func testParserPreservesAmbiguousNumbers() {
        XCTAssertEqual(ShoppingInputParser.parse("בשר טחון 2 חב"), .init(name: "בשר טחון", quantity: 2, unit: "חבילות"))
        for name in ["חלב 3%", "7 up", "ביצים 12", "קמח 0 חב"] {
            XCTAssertEqual(ShoppingInputParser.parse(name).name, name)
        }
    }
    func testSessionBoundaryDoesNotAlterOpenItems() {
        let id = UUID()
        let first = Purchase(id: UUID(), productID: id, quantity: 1, purchasedAt: .init(timeIntervalSince1970: 0), sourceItemID: UUID())
        var second = first
        second.id = UUID(); second.purchasedAt = .init(timeIntervalSince1970: 3 * 3600)
        XCTAssertEqual(ShoppingSession.groups([second, first]).count, 2)
    }
}
