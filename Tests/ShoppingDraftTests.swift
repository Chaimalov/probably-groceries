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
