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
        XCTAssertTrue(app.buttons["נקנה \(first)"].waitForExistence(timeout: 10))
        XCTAssertTrue(field.exists, "Enter should keep inline add available")
        field.typeText(second + "\n")
        XCTAssertTrue(app.buttons["נקנה \(second)"].waitForExistence(timeout: 10))

        app.buttons["עריכת כמות והערות עבור \(first)"].tap()
        app.buttons["הגדלת כמות"].tap()
        XCTAssertEqual(app.staticTexts["inlineQuantity"].label, "2")
        let note = app.descendants(matching: .any)["itemNoteField"]
        note.tap()
        note.typeText("ללא סוכר")

        app.terminate()
        app.launch()
        let buy = app.buttons["נקנה \(first)"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Items should survive relaunch")
        app.buttons["עריכת כמות והערות עבור \(first)"].tap()
        XCTAssertEqual(app.staticTexts["inlineQuantity"].label, "2")
        XCTAssertTrue(app.descendants(matching: .any)["itemNoteField"].exists)
        buy.tap()
        XCTAssertTrue(app.buttons["ביטול"].waitForExistence(timeout: 10))
        app.buttons["ביטול"].tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
    }

    func testSectionCreationAndStoreSwitching() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let section = "Dairy \(UUID().uuidString.prefix(6))"
        let shop = "Corner \(UUID().uuidString.prefix(6))"
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["מחלקה חדשה"].tap()
        let sectionAlert = app.alerts["מחלקה חדשה"]
        XCTAssertTrue(sectionAlert.waitForExistence(timeout: 10))
        sectionAlert.textFields["שם המחלקה"].typeText(section)
        sectionAlert.buttons["יצירה"].tap()
        XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 10))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["רשימה חדשה לחנות"].tap()
        let alert = app.alerts["רשימה חדשה לחנות"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.textFields["שם החנות"].typeText(shop)
        alert.buttons["יצירה"].tap()
        XCTAssertTrue(app.navigationBars[shop].waitForExistence(timeout: 10))
    }
}
