import XCTest

final class ShoppingPresentationTests: XCTestCase {
    private func item() -> ShoppingItem {
        ShoppingItem(id: UUID(), productID: UUID(), quantity: 1, addedAt: .now)
    }
    private func purchase(_ item: ShoppingItem) -> Purchase {
        Purchase(id: item.id, productID: item.productID, quantity: item.quantity,
                 purchasedAt: .now, sourceItemID: item.id, listID: item.listID)
    }

    func testFiveConsecutivePurchasesKeepEveryTapTargetInPlace() {
        let original = (0..<5).map { _ in item() }
        var active = original
        var purchases: [Purchase] = []
        var presentation = ShoppingPresentation()
        for row in original {
            presentation.retain(row, among: presentation.rows(active: active, purchases: purchases, listID: row.listID))
            active.removeAll { $0.id == row.id }
            purchases.append(purchase(row))
            XCTAssertEqual(presentation.rows(active: active, purchases: purchases, listID: row.listID).map(\.id), original.map(\.id))
        }
        presentation.reset()
        XCTAssertTrue(presentation.rows(active: active, purchases: purchases, listID: original[0].listID).isEmpty)
    }

    func testUndoUsesLiveEditedRowAndNeverDuplicatesOrLeaksToAnotherList() {
        let first = item(), second = item()
        var presentation = ShoppingPresentation()
        presentation.retain(first, among: [first, second])
        var restored = first
        restored.quantity = 7
        let rows = presentation.rows(active: [restored, second], purchases: [], listID: first.listID)
        XCTAssertEqual(rows.map(\.id), [first.id, second.id])
        XCTAssertEqual(rows.first?.quantity, 7)
        XCTAssertTrue(presentation.rows(active: [], purchases: [purchase(first)], listID: UUID()).isEmpty)
        // A deleted/corrected purchase must not leave a phantom checked row.
        XCTAssertEqual(presentation.rows(active: [second], purchases: [], listID: first.listID).map(\.id), [second.id])
    }
}
