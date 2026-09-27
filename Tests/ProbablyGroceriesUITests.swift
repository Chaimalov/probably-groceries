import XCTest

final class ProbablyGroceriesUITests: XCTestCase {
    func testInlineAddEnterPurchaseUndoAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let first = "Milk \(UUID().uuidString.prefix(8))"
        let second = "Bread \(UUID().uuidString.prefix(8))"
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(first + "\n")
        let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", first)).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        XCTAssertTrue(field.exists, "Enter should keep inline add available")
        field.typeText(second + "\n")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", second)).firstMatch.waitForExistence(timeout: 10))

        let details = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "עריכת כמות", first)).firstMatch
        details.tap()
        app.buttons["הגדלת כמות"].tap()
        XCTAssertEqual(app.staticTexts["inlineQuantity"].label, "2")
        app.buttons["בחירת יחידת מידה"].tap()
        app.buttons["חבילות"].tap()
        let note = app.descendants(matching: .any)["itemNoteField"]
        note.tap()
        note.typeText("ללא סוכר")

        app.terminate()
        app.launch()
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Items should survive relaunch")
        details.tap()
        XCTAssertEqual(app.staticTexts["inlineQuantity"].label, "2")
        XCTAssertEqual(app.buttons["בחירת יחידת מידה"].value as? String, "חבילות")
        XCTAssertTrue(app.descendants(matching: .any)["itemNoteField"].exists)
        buy.tap()
        XCTAssertTrue(app.buttons["ביטול"].waitForExistence(timeout: 10))
        app.buttons["ביטול"].tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
    }

    func testMultipleSelectionFlagsItemsTogether() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let first = "Milk \(UUID().uuidString.prefix(8))"
        let second = "Bread \(UUID().uuidString.prefix(8))"
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["inlineAddField"]
        field.tap()
        field.typeText(first + "\n")
        field.typeText(second + "\n")
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["בחירת פריטים"].tap()
        app.staticTexts[first].tap()
        app.staticTexts[second].tap()
        XCTAssertTrue(app.staticTexts["2 נבחרו"].waitForExistence(timeout: 5))
        app.buttons["דגל"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", first)).firstMatch.waitForExistence(timeout: 5))
    }

    func testSectionCreationAndStoreSwitching() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let section = "Dairy \(UUID().uuidString.prefix(6))"
        let shop = "Corner \(UUID().uuidString.prefix(6))"
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["מקטע חדש"].tap()
        let sectionAlert = app.alerts["מקטע חדש"]
        XCTAssertTrue(sectionAlert.waitForExistence(timeout: 10))
        sectionAlert.textFields["שם המקטע"].typeText(section)
        sectionAlert.buttons["יצירה"].tap()
        XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 10))

        app.buttons["הוספת מוצר למקטע \(section)"].tap()
        let item = "Eggs \(UUID().uuidString.prefix(6))"
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText(item + "\n")
        XCTAssertTrue(app.buttons["נקנה \(item)"].waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", section)).firstMatch.tap()
        XCTAssertFalse(app.buttons["נקנה \(item)"].exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", section)).firstMatch.tap()
        XCTAssertTrue(app.buttons["נקנה \(item)"].waitForExistence(timeout: 10))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["רשימה חדשה לחנות"].tap()
        let alert = app.alerts["רשימה חדשה לחנות"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.textFields["שם החנות"].typeText(shop)
        alert.buttons["יצירה"].tap()
        XCTAssertTrue(app.navigationBars[shop].waitForExistence(timeout: 10))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["צבע וסמל הרשימה"].tap()
        app.buttons["צבע blue"].tap()
        app.buttons["סמל basket"].tap()
        app.buttons["שמירה"].tap()
        app.terminate()
        app.launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["צבע וסמל הרשימה"].tap()
        XCTAssertTrue(app.buttons["צבע blue"].isSelected)
        XCTAssertTrue(app.buttons["סמל basket"].isSelected)
    }
}
