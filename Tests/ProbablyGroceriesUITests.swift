import XCTest

final class ProbablyGroceriesUITests: XCTestCase {
    func testStoreListsUrgencyAndCategories() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let item = "Oats \(UUID().uuidString.prefix(8))"
        let storeName = "Corner \(UUID().uuidString.prefix(6))"
        app.buttons["הוספת מוצר"].tap()
        let nameField = app.textFields["מה צריך לקנות?"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(item)
        let departmentField = app.textFields["מחלקה (לא חובה)"]
        departmentField.tap()
        departmentField.typeText("Dairy")
        let categoryField = app.textFields["קטגוריה (לא חובה)"]
        categoryField.tap()
        categoryField.typeText("Pantry")
        app.switches["דחוף"].tap()
        app.buttons["הוספה"].tap()
        XCTAssertTrue(app.staticTexts[item].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["דחוף"].exists)
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["קיבוץ לפי מחלקה וקטגוריה"].tap()
        XCTAssertTrue(app.staticTexts["Dairy"].exists)

        app.buttons["בחירת חנות, קניות"].tap()
        app.buttons["רשימה חדשה לחנות"].tap()
        let alert = app.alerts["רשימה חדשה לחנות"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.textFields["שם החנות"].typeText(storeName)
        alert.buttons["יצירה"].tap()
        XCTAssertTrue(app.buttons["בחירת חנות, \(storeName)"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[item].exists)

        app.buttons["בחירת חנות, \(storeName)"].tap()
        app.buttons["קניות"].tap()
        XCTAssertTrue(app.staticTexts[item].waitForExistence(timeout: 10))
        app.buttons["אפשרויות נוספות"].tap()
        app.buttons["מיון לפי מסלול הקנייה"].tap()
    }

    func testAddBuyUndoAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let name = "Milk \(UUID().uuidString.prefix(8))"
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["מה צריך לקנות?"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons["הוספה"].tap()

        let buy = app.buttons["נקנה \(name)"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Item should survive relaunch")

        buy.tap()
        XCTAssertTrue(app.buttons["ביטול"].waitForExistence(timeout: 10))
        app.buttons["ביטול"].tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
    }

    func testEditQuantityCorrectPurchaseAndUndoFromHistory() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let name = "Eggs \(UUID().uuidString.prefix(8))"
        app.buttons["הוספת מוצר"].tap()
        let field = app.textFields["מה צריך לקנות?"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons["הוספה"].tap()

        let editItem = app.buttons["עריכת כמות עבור \(name)"]
        XCTAssertTrue(editItem.waitForExistence(timeout: 10))
        editItem.tap()
        let stepper = app.steppers["quantityStepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        stepper.buttons["quantityStepper-Increment"].tap()
        app.buttons["שמירה"].tap()
        app.swipeDown()
        capture("Shopping list with quantity", in: app)

        app.buttons["נקנה \(name)"].tap()
        app.buttons["לכל הקניות"].tap()
        capture("Purchase history", in: app)
        let editPurchase = app.buttons["עריכת כמות שנקנתה עבור \(name)"]
        XCTAssertTrue(editPurchase.waitForExistence(timeout: 10))
        XCTAssertEqual(editPurchase.value as? String, "כמות 2")
        editPurchase.tap()
        let purchaseStepper = app.steppers["quantityStepper"]
        XCTAssertTrue(purchaseStepper.waitForExistence(timeout: 10))
        purchaseStepper.buttons["quantityStepper-Increment"].tap()
        capture("Correcting a purchase", in: app)
        app.buttons["שמירה"].tap()
        XCTAssertEqual(editPurchase.value as? String, "כמות 3")

        app.buttons["ביטול קנייה"].firstMatch.tap()
        XCTAssertFalse(editPurchase.exists)
        app.buttons["סיום"].tap()
        XCTAssertTrue(app.buttons["נקנה \(name)"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["עריכת כמות עבור \(name)"].value as? String, "כמות 3")
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
