import XCTest

final class ShoppingRouteFreezeTests: XCTestCase {
    func testConsecutiveCheckoffsAndNewItemsPreserveOriginalUndoPositions() {
        var rows = (0..<5).map { _ in
            ShoppingItem(id: UUID(), productID: UUID(), quantity: 1, addedAt: .now)
        }
        let original = rows
        var undoPositions: [UUID: Int] = [:]
        while !rows.isEmpty {
            let frozen = ShoppingRouteOrder.frozenPositions(for: rows)
            for index in rows.indices { rows[index].manualOrder = frozen[rows[index].id] }
            let bought = rows.removeFirst()
            undoPositions[bought.id] = frozen[bought.id]
        }
        XCTAssertEqual(original.map { undoPositions[$0.id]! }, [0, 1, 2, 3, 4])
        var survivor = original[4]
        survivor.manualOrder = 4
        let added = ShoppingItem(id: UUID(), productID: UUID(), quantity: 1, addedAt: .now)
        let positions = ShoppingRouteOrder.frozenPositions(for: [survivor, added])
        XCTAssertEqual(positions[survivor.id], 4)
        XCTAssertEqual(positions[added.id], 5, "Adding during a trip must not move before surviving rows")
    }
}
