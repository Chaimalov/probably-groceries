import XCTest

final class OrganizationTests: XCTestCase {
    private func fixture() -> ShoppingData {
        let product = Product(id: UUID(), name: "חלב", usualQuantity: 1, department: "חלב")
        let item = ShoppingItem(id: UUID(), productID: product.id, quantity: 3, addedAt: .now)
        let purchase = Purchase(id: UUID(), productID: product.id, quantity: 1, purchasedAt: .now, sourceItemID: UUID())
        return ShoppingData(lists: [ShoppingList(id: ShoppingList.defaultID, name: "קניות", sections: ["חלב", "ניקיון"])],
                            products: [product], items: [item], purchases: [purchase])
    }

    func testRenameAndDeleteLegacySectionNeverReappearsFromHistory() throws {
        var data = fixture()
        XCTAssertTrue(data.editSection(in: ShoppingList.defaultID, oldName: "חלב", name: "מקרר",
                                       appearance: SectionAppearance(symbol: "snowflake", tint: "blue")))
        XCTAssertEqual(data.sectionNames(in: ShoppingList.defaultID), ["מקרר", "ניקיון", "אחר"])
        XCTAssertEqual(data.items[0].sectionName, "מקרר")
        XCTAssertEqual(data.purchases[0].sectionName, "מקרר")
        data.deleteSection(in: ShoppingList.defaultID, name: "מקרר", includingItems: false)
        XCTAssertEqual(data.sectionName(for: data.items[0]), "אחר")
        XCTAssertEqual(data.purchases.count, 1)
        XCTAssertEqual(data.purchases[0].sectionName, "")
        XCTAssertEqual(data.sectionNames(in: ShoppingList.defaultID), ["ניקיון", "אחר"])
        let restored = try JSONDecoder().decode(ShoppingData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(restored.sectionNames(in: ShoppingList.defaultID), ["ניקיון", "אחר"])
    }

    func testSectionEditsAreScopedAndRejectDuplicateNames() {
        var data = fixture()
        let other = UUID()
        var item = data.items[0]; item.id = UUID(); item.listID = other
        data.items.append(item)
        data.lists.append(ShoppingList(id: other, name: "אחרת", sections: ["חלב"]))
        XCTAssertFalse(data.editSection(in: ShoppingList.defaultID, oldName: "חלב", name: "ניקיון",
                                        appearance: SectionAppearance(symbol: "basket", tint: "green")))
        data.deleteSection(in: ShoppingList.defaultID, name: "חלב", includingItems: true)
        XCTAssertEqual(data.items.map(\.id), [item.id])
        XCTAssertEqual(data.sectionNames(in: other), ["חלב", "אחר"])
        XCTAssertEqual(data.purchases.count, 1)
    }

    func testBadgeDefaultsFiltersQuantitiesAndDeletedLists() {
        var data = fixture()
        let suite = "OrganizationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func count() -> Int { BadgePolicy.count(in: data, selectedListID: ShoppingList.defaultID, defaults: defaults) }
        XCTAssertEqual(count(), 0)
        defaults.set(true, forKey: "shoppingBadgeEnabled")
        XCTAssertEqual(count(), 1)
        defaults.set(true, forKey: "shoppingBadgeQuantities")
        XCTAssertEqual(count(), 3)
        defaults.set(true, forKey: "shoppingBadgeUrgentOnly")
        XCTAssertEqual(count(), 0)
        data.items[0].isUrgent = true
        XCTAssertEqual(count(), 3)
        data.items[0].unavailable = true
        defaults.set(true, forKey: "shoppingBadgeExcludeUnavailable")
        XCTAssertEqual(count(), 0)
        defaults.set(false, forKey: "shoppingBadgeExcludeUnavailable")
        defaults.set("chosen", forKey: "shoppingBadgeLists")
        XCTAssertEqual(count(), 0)
        defaults.set([ShoppingList.defaultID.uuidString], forKey: "shoppingBadgeListIDs")
        XCTAssertEqual(count(), 3)
        data.lists = []
        XCTAssertEqual(count(), 0)
    }

    func testOldDataDecodesAndClarificationSurvivesSyncPayload() throws {
        let old = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Old\"}".utf8)
        XCTAssertNil(try JSONDecoder().decode(ShoppingList.self, from: old).sectionStyles)
        var data = fixture()
        data.items[0].clarification = ItemClarification(question: "איזה?", answer: "אבקה")
        data.items[0].unavailable = true
        let records = SyncJournal.records(in: data)
        let payload = try XCTUnwrap(records["item_\(data.items[0].id.uuidString)"])
        let restored = try JSONDecoder().decode(ShoppingItem.self, from: payload)
        XCTAssertEqual(restored.clarification, data.items[0].clarification)
        XCTAssertEqual(restored.unavailable, true)
    }
}
