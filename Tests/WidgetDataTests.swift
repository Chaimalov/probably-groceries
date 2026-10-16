import XCTest

final class WidgetDataTests: XCTestCase {
    func testOldSnapshotsWithoutUnitStillDecode() throws {
        let list = UUID(), item = UUID()
        let bytes = Data("""
        {"listID":"\(list)","title":"קניות","tintName":"green","total":1,
         "rows":[{"id":"\(item)","name":"חלב","quantity":2}]}
        """.utf8)
        let snapshot = try JSONDecoder().decode(GroceryWidgetSnapshot.self, from: bytes)
        XCTAssertNil(snapshot.rows.first?.unit)
        XCTAssertEqual(snapshot.rows.first?.quantity, 2)
    }

    func testAllRowsAreReachableAndLastPageWraps() {
        var seen: [Int] = []
        var offset = 0
        repeat {
            let page = WidgetPage(count: 27, offset: offset, capacity: 12)
            seen.append(contentsOf: page.range)
            offset = page.next
        } while offset != 0
        XCTAssertEqual(seen, Array(0..<27))
    }

    func testPurchasesRemoveFinalPageWithoutLeavingWidgetEmpty() {
        let page = WidgetPage(count: 10, offset: 12, capacity: 6)
        XCTAssertEqual(page.range, 6..<10)
        XCTAssertEqual(page.previous, 0)
        XCTAssertEqual(page.next, 0)
    }

    func testEmptyListAndInvalidOffsetsAreSafe() {
        XCTAssertEqual(WidgetPage(count: 0, offset: 100, capacity: 0).range, 0..<0)
        XCTAssertEqual(WidgetPage(count: 2, offset: -10, capacity: 0).range, 0..<1)
    }
}
