import XCTest

final class ProbablyGroceriesUITests: XCTestCase {
    func testTouchAndHoldReordersWithoutBuyingAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        let shop = "Drag \(UUID().uuidString.prefix(6))"
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["רשימה חדשה לחנות"].tap()
        let alert = app.alerts["רשימה חדשה לחנות"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.textFields["שם החנות"].typeText(shop)
        alert.buttons["יצירה"].tap()
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Drag Alpha\nDrag Beta\nDrag Gamma\n")
        // Relaunch closes the keyboard so drag uses the ordinary shopping state.
        app.terminate()
        app.launch()
        let alpha = app.staticTexts["Drag Alpha"]
        let gamma = app.staticTexts["Drag Gamma"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.7, thenDragTo:
                gamma.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
                    .withOffset(CGVector(dx: 0, dy: 8)))
        let reordered = NSPredicate { _, _ in alpha.frame.minY > gamma.frame.minY }
        expectation(for: reordered, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "נקנה")).count, 3)
        XCTAssertFalse(app.buttons["ביטול"].exists, "Reorder must not create purchase history")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Touch and hold reorder"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(alpha.frame.minY, gamma.frame.minY)
    }

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

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                         section, "הוספת מוצר למקטע")).firstMatch.tap()
        let item = "Eggs \(UUID().uuidString.prefix(6))"
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(item + "\n")
        let buy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", item, "נקנה")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "List with section and compact rows"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let header = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", section, "מוצרים")).firstMatch
        header.tap()
        XCTAssertFalse(buy.exists)
        header.tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))

        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["סידור מוצרים"].tap()
        let reorderScreenshot = XCTAttachment(screenshot: app.screenshot())
        reorderScreenshot.name = "Native reorder handles"
        reorderScreenshot.lifetime = .keepAlways
        add(reorderScreenshot)
        app.buttons["סיום"].tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["רשימה חדשה לחנות"].tap()
        let alert = app.alerts["רשימה חדשה לחנות"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.textFields["שם החנות"].typeText(shop)
        alert.buttons["יצירה"].tap()
        XCTAssertTrue(app.navigationBars[shop].waitForExistence(timeout: 10))

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["צבע וסמל הרשימה"].tap()
        let blue = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "blue")).firstMatch
        let basket = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "basket")).firstMatch
        blue.tap()
        basket.tap()
        app.buttons["שמירה"].tap()
        app.terminate()
        app.launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["צבע וסמל הרשימה"].tap()
        XCTAssertTrue(blue.isSelected)
        XCTAssertTrue(basket.isSelected)
    }
}

