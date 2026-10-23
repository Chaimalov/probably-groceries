import Foundation
import XCTest

final class ProductLearningTests: XCTestCase {
    private func fixture() -> (ShoppingData, UUID, UUID, Date) {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var a = Product(id: UUID(), name: "ביצים", usualQuantity: 1)
        let b = Product(id: UUID(), name: "בייצים", usualQuantity: 1)
        a.learningLinks = [ProductLearningLink(listID: ShoppingList.defaultID, targetID: b.id,
            sourceName: a.name, targetName: b.name, sourceUnit: nil, targetUnit: nil,
            model: "mercury-decide", policyVersion: "product-identity-v1", probability: 0.995,
            confidence: 0.99, createdAt: now)]
        let purchases = [(a.id, 28.0), (b.id, 21.0), (a.id, 14.0)].map { id, days in
            Purchase(id: UUID(), productID: id, quantity: 1,
                purchasedAt: now.addingTimeInterval(-days * 86400), sourceItemID: UUID())
        }
        return (ShoppingData(products: [a, b], purchases: purchases), a.id, b.id, now)
    }

    func testLinkedNamesLearnFromCombinedHistoryAndYieldOneSuggestion() throws {
        let (data, a, b, now) = fixture()
        let restored = try JSONDecoder().decode(ShoppingData.self, from: JSONEncoder().encode(data))
        let evaluations = PredictionEngine.evaluate(restored, now: now)
        XCTAssertEqual(evaluations.filter { $0.tier != nil }.count, 1)
        XCTAssertEqual(evaluations.first { $0.id == a }?.distinctTripCount, 3)
        XCTAssertEqual(evaluations.first { $0.id == b }?.purchaseCount, 3)
        XCTAssertEqual(restored.purchases.map(\.productID), data.purchases.map(\.productID))
        XCTAssertEqual(restored.products.map(\.name), ["ביצים", "בייצים"])
    }

    func testActiveAliasOrDeferredAliasSuppressesWholeGroup() {
        var (data, _, b, now) = fixture()
        data.items = [ShoppingItem(id: UUID(), productID: b, quantity: 1, addedAt: now)]
        XCTAssertTrue(PredictionEngine.evaluate(data, now: now).allSatisfy { $0.tier == nil })
        data.items = []
        data.deferrals = [Deferral(productID: b, until: now.addingTimeInterval(86400))]
        XCTAssertTrue(PredictionEngine.evaluate(data, now: now).allSatisfy { $0.tier == nil })
    }

    func testRenameUnitChangeOrDifferentListInvalidatesLink() {
        let (original, a, _, now) = fixture()
        var renamed = original
        renamed.products[1].name = "ביצי שוקולד"
        XCTAssertEqual(ProductLearning.groups(in: renamed, listID: ShoppingList.defaultID)[a]?.count, 1)
        var units = original
        units.products[1].preferredUnit = "חבילות"
        XCTAssertEqual(ProductLearning.groups(in: units, listID: ShoppingList.defaultID)[a]?.count, 1)
        XCTAssertEqual(ProductLearning.groups(in: original, listID: UUID())[a]?.count, 1)
        XCTAssertEqual(PredictionEngine.evaluate(renamed, now: now).filter { $0.tier != nil }.count, 0)
    }

    func testCyclesTerminateAndWeakLinksAreIgnored() {
        var (data, a, b, _) = fixture()
        var reverse = data.products[0].learningLinks![0]
        reverse.targetID = a; reverse.sourceName = "בייצים"; reverse.targetName = "ביצים"
        data.products[1].learningLinks = [reverse]
        XCTAssertEqual(ProductLearning.groups(in: data, listID: ShoppingList.defaultID)[b]?.count, 2)
        data.products[0].learningLinks?[0].probability = 0.5
        data.products[1].learningLinks?[0].confidence = 0.5
        XCTAssertEqual(ProductLearning.groups(in: data, listID: ShoppingList.defaultID)[a]?.count, 1)
    }
}
