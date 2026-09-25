import XCTest

final class PredictionEngineTests: XCTestCase {
    func testShoppingRouteUsesExactCheckOffOrderAcrossTrips() {
        let milk = UUID(), bread = UUID(), eggs = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func purchase(_ product: UUID, day: Int, minute: Int) -> Purchase {
            Purchase(id: UUID(), productID: product, quantity: 1,
                     purchasedAt: start.addingTimeInterval(Double(day * 86_400 + minute * 60)),
                     sourceItemID: UUID())
        }
        let events = [
            purchase(eggs, day: 8, minute: 22),
            purchase(bread, day: 0, minute: 15),
            purchase(milk, day: 8, minute: 3),
            purchase(eggs, day: 0, minute: 21),
            purchase(bread, day: 8, minute: 12),
            purchase(milk, day: 0, minute: 2)
        ]
        let order = ShoppingRouteOrder.positions(from: events)
        XCTAssertLessThan(order[milk]!, order[bread]!)
        XCTAssertLessThan(order[bread]!, order[eggs]!)

        // Removing a mistaken check-off removes that observation from the learned route.
        let corrected = ShoppingRouteOrder.positions(from: events.filter {
            $0.productID != eggs || $0.purchasedAt < start.addingTimeInterval(86_400)
        })
        XCTAssertNotNil(corrected[eggs])
        XCTAssertLessThan(corrected[milk]!, corrected[eggs]!)
    }

    private let origin = Date(timeIntervalSince1970: 1_767_225_600)

    func testWeeklyStapleUsesRecentMedianQuantity() {
        let data = fixture(days: [0, 7, 14], quantities: [1, 2, 2])
        let result = evaluation(data, day: 22)
        XCTAssertEqual(result.tier, .likely)
        XCTAssertEqual(result.quantity, 2)
        XCTAssertEqual(result.intervalDays ?? 0, 7, accuracy: 0.01)
    }

    func testOneOffAndTwoPurchasesNeverSuggest() {
        XCTAssertNil(evaluation(fixture(days: [0], quantities: [1]), day: 30).tier)
        XCTAssertNil(evaluation(fixture(days: [0, 7], quantities: [1, 1]), day: 30).tier)
    }

    func testBulkPurchaseWaitsForLongInterval() {
        let data = fixture(days: [0, 45, 90], quantities: [6, 8, 8])
        XCTAssertNil(evaluation(data, day: 100).tier)
        XCTAssertEqual(evaluation(data, day: 139).tier, .likely)
        XCTAssertEqual(evaluation(data, day: 139).quantity, 8)
    }

    func testSameTripPurchasesAndDeferralDoNotSuggest() {
        var data = fixture(days: [0, 0.1, 7], quantities: [1, 1, 1])
        XCTAssertEqual(evaluation(data, day: 30).distinctTripCount, 2)
        XCTAssertNil(evaluation(data, day: 30).tier)
        data.purchases.append(Purchase(id: UUID(), productID: data.products[0].id,
                                       quantity: 1, purchasedAt: date(14), sourceItemID: UUID()))
        data.deferrals.append(Deferral(productID: data.products[0].id, until: date(31)))
        XCTAssertNil(evaluation(data, day: 30).tier)
        XCTAssertEqual(evaluation(data, day: 32).tier, .likely)
        data.items.append(ShoppingItem(id: UUID(), productID: data.products[0].id,
                                       quantity: 1, addedAt: date(32)))
        XCTAssertNil(evaluation(data, day: 32).tier)
    }

    private func fixture(days: [Double], quantities: [Int]) -> ShoppingData {
        let product = Product(id: UUID(), name: "Milk", usualQuantity: 1)
        let purchases = zip(days, quantities).map { day, quantity in
            Purchase(id: UUID(), productID: product.id, quantity: quantity,
                     purchasedAt: date(day), sourceItemID: UUID())
        }
        return ShoppingData(products: [product], items: [], purchases: purchases, deferrals: [])
    }

    private func date(_ day: Double) -> Date { origin.addingTimeInterval(day * 86_400) }

    private func evaluation(_ data: ShoppingData, day: Double) -> PredictionEvaluation {
        PredictionEngine.evaluate(data, now: date(day))[0]
    }
}
