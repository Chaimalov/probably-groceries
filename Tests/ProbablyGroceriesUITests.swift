import XCTest
import UIKit

final class ProbablyGroceriesUITests: XCTestCase {
    func testPreparationCloseResumeExcludeAndConfirmOnce() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "בחירת חנות")).firstMatch.tap()
        app.buttons["רשימה חדשה לחנות"].tap()
        let alert = app.alerts["רשימה חדשה לחנות"]
        alert.textFields["שם החנות"].typeText("Draft \(UUID().uuidString.prefix(6))")
        alert.buttons["יצירה"].tap()
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons.matching(identifier: "קנייה חדשה").firstMatch.tap()
        let field = app.textFields["מוצר נוסף"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Draft Milk 2 חב\n")
        let name = "Draft Milk"
        XCTAssertTrue(app.textFields["שם המוצר"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "החרגת", name)).firstMatch.tap()
        app.buttons.matching(identifier: "סגירה").firstMatch.tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", name)).firstMatch.exists)
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons.matching(identifier: "קנייה חדשה").firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "החזרת", name)).firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "החזרת", name)).firstMatch.tap()
        app.buttons["אישור"].tap()
        let bought = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", name))
        let buy = bought.firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        XCTAssertEqual(bought.count, 1)
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons.matching(identifier: "קנייה חדשה").firstMatch.tap()
        XCTAssertTrue(app.textFields["מוצר נוסף"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["שם המוצר"].exists, "Confirmed draft must not reopen as unfinished")
        app.buttons.matching(identifier: "סגירה").firstMatch.tap()
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Confirmed preparation"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testTouchAndHoldReordersWithoutBuyingAndSurvivesRelaunch() {
        continueAfterFailure = false
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
        for name in ["Drag Alpha", "Drag Beta", "Drag Gamma"] {
            field.typeText(name + "\n")
            let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", name)).firstMatch
            XCTAssertTrue(buy.waitForExistence(timeout: 5))
        }
        // Relaunch closes the keyboard so drag uses the ordinary shopping state.
        app.terminate()
        app.launch()
        let alpha = app.buttons["Drag Alpha"]
        let gamma = app.buttons["Drag Gamma"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo:
                gamma.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
                    .withOffset(CGVector(dx: 0, dy: 8)),
                withVelocity: .slow, thenHoldForDuration: 1.0)
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
        for name in ["Drag One", "Drag Two"] {
            app.buttons["אפשרויות נוספות"].tap()
            app.buttons["מקטע חדש"].tap()
            let sectionAlert = app.alerts["מקטע חדש"]
            XCTAssertTrue(sectionAlert.waitForExistence(timeout: 5))
            sectionAlert.textFields["שם המקטע"].typeText(name)
            sectionAlert.buttons["יצירה"].tap()
        }
        let one = app.staticTexts["Drag One"]
        let two = app.staticTexts["Drag Two"]
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        one.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo:
                two.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
                    .withOffset(CGVector(dx: 0, dy: 4)),
                withVelocity: .slow, thenHoldForDuration: 1.0)
        expectation(for: NSPredicate { _, _ in one.frame.minY > two.frame.minY }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launch()
        XCTAssertTrue(one.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(one.frame.minY, two.frame.minY, "Section order must also persist")
        for appearance in ["Light", "Dark"] {
            app.terminate()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment["UITEST_APPEARANCE"] = appearance.lowercased()
            app.launch()
            XCTAssertTrue(alpha.waitForExistence(timeout: 10))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.3, dy: alpha.frame.midY))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.65, dy: alpha.frame.midY))
            start.press(forDuration: 0.05, thenDragTo: end)
            XCTAssertTrue(app.buttons["הסר"].waitForExistence(timeout: 5))
            let swipe = XCTAttachment(screenshot: app.screenshot())
            swipe.name = "Icon swipe actions - \(appearance)"
            swipe.lifetime = .keepAlways
            add(swipe)
        }
    }

    func testInlineAddEnterPurchaseUndoAndPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let first = "Milk \(UUID().uuidString.prefix(8))"
        let second = "Bread \(UUID().uuidString.prefix(8))"
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(first + " 5 יח׳")
        app.buttons["newItemQuantityButton"].tap()
        XCTAssertEqual(app.staticTexts["newItemQuantity"].label, "5")
        for _ in 0..<4 { app.buttons["הפחתת כמות למוצר חדש"].tap() }
        XCTAssertEqual(app.staticTexts["newItemQuantity"].label, "1")
        field.typeText("\n")
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
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["הצגת נקנו לאחרונה"].tap()
        XCTAssertFalse(app.buttons["ביטול"].exists)
        app.terminate()
        app.launch()
        XCTAssertFalse(app.buttons["ביטול"].exists, "Visibility preference should survive relaunch")
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["הצגת נקנו לאחרונה"].tap()
        XCTAssertTrue(app.buttons["ביטול"].waitForExistence(timeout: 10), "Hiding purchases must not delete their events")
        app.buttons["ביטול"].tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
    }

    func testInlineEditorFocusAndAdaptiveLayout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        let name = "Editor \(UUID().uuidString.prefix(8))"
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["הגדלת כמות למוצר חדש"].exists)
        field.typeText(name)
        app.buttons["הערה"].tap()
        let draftNote = app.descendants(matching: .any)["newItemNoteField"]
        XCTAssertTrue(draftNote.waitForExistence(timeout: 5))
        draftNote.tap()
        draftNote.typeText("Original note")
        app.buttons["סיום עריכה"].tap()
        let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", name)).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "Done must commit a nonempty draft")
        XCTAssertFalse(field.exists, "A finished editor must leave no permanent input row")
        app.buttons[name].tap()
        let rename = app.textFields["שם המוצר"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.typeText(" Updated")
        let note = app.descendants(matching: .any)["itemNoteField"]
        note.tap()
        note.typeText(" Updated")
        XCTAssertTrue(note.exists, "Moving focus to the note must keep this editor open")
        app.buttons["סיום עריכה"].tap()
        let updated = name + " Updated"
        XCTAssertTrue(app.buttons[updated].waitForExistence(timeout: 5))
        app.buttons[updated].tap()
        app.buttons["פרטי מוצר"].tap()
        XCTAssertTrue(app.textFields["אופציונלי"].waitForExistence(timeout: 5))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.buttons["אפשרויות נוספות"].isHittable, "The list stays accessible beside the iPad inspector")
        }
        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "Adaptive item details"
        details.lifetime = .keepAlways
        add(details)
        app.buttons.matching(identifier: "סגירה").firstMatch.tap()
        app.buttons["סיום עריכה"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons[updated].waitForExistence(timeout: 10))
        app.buttons[updated].tap()
        XCTAssertEqual(app.descendants(matching: .any)["itemNoteField"].value as? String, "Original note Updated")
        app.buttons["סיום עריכה"].tap()

        // Return in a saved row starts a focused draft directly below it.
        app.buttons[updated].tap()
        let inserted = "Between \(UUID().uuidString.prefix(6))"
        app.textFields["שם המוצר"].typeText("\n")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(inserted + "\n")
        XCTAssertTrue(app.buttons[inserted].waitForExistence(timeout: 5), "Return must focus the new row without a tap")
        XCTAssertTrue(field.exists, "Return must continue adding after the inserted row")
        app.buttons["סיום עריכה"].tap()
        XCTAssertLessThan(app.buttons[updated].frame.minY, app.buttons[inserted].frame.minY)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons[inserted].waitForExistence(timeout: 10), "Inserted rows persist")
        XCTAssertLessThan(app.buttons[updated].frame.minY, app.buttons[inserted].frame.minY)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", updated)).firstMatch.tap()
        XCTAssertTrue(app.buttons["ביטול"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "ביטול").firstMatch.tap()
        XCTAssertTrue(app.buttons[updated].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["הוספת מוצר"].exists, "Empty sections appear in normal shopping mode")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[section].waitForExistence(timeout: 10), "Empty sections remain visible after relaunch")

        app.buttons["הוספת מוצר"].tap()
        let item = "Eggs \(UUID().uuidString.prefix(6))"
        let field = app.textFields["inlineAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(item)
        app.buttons["בחירת מקטע למוצר חדש"].tap()
        app.buttons[section].tap()
        field.tap()
        field.typeText("\n")
        app.buttons["סיום עריכה"].tap()
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
        app.buttons[item].tap()
        app.textFields["שם המוצר"].typeText("\n")
        let nextItem = "Next \(UUID().uuidString.prefix(6))"
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(nextItem + "\n")
        app.buttons["סיום עריכה"].tap()
        let nextBuy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "נקנה", nextItem)).firstMatch
        XCTAssertTrue(nextBuy.waitForExistence(timeout: 5))
        XCTAssertLessThan(buy.frame.minY, nextBuy.frame.minY)
        header.tap()
        XCTAssertFalse(nextBuy.exists, "Return must add to the same section")
        header.tap()
        XCTAssertTrue(nextBuy.waitForExistence(timeout: 5))
        nextBuy.tap()
        buy.tap()
        XCTAssertTrue(header.exists, "Purchasing the last product must leave its section visible")

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


