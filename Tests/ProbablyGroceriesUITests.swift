import XCTest

final class ProbablyGroceriesUITests: XCTestCase {
    func testStoreListsUrgencyAndCategories() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let item = "Oats \(UUID().uuidString.prefix(8))"
        let storeName = "Corner \(UUID().uuidString.prefix(6))"
        app.buttons["Add item"].tap()
        let nameField = app.textFields["What do you need?"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(item)
        let categoryField = app.textFields["Category (optional)"]
        categoryField.tap()
        categoryField.typeText("Pantry")
        app.switches["Urgent"].tap()
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts[item].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["Urgent"].exists)

        app.buttons["Choose store list, Groceries"].tap()
        app.buttons["New store list"].tap()
        let alert = app.alerts["New store list"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.textFields["Store name"].typeText(storeName)
        alert.buttons["Create"].tap()
        XCTAssertTrue(app.buttons["Choose store list, \(storeName)"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[item].exists)

        app.buttons["Choose store list, \(storeName)"].tap()
        app.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts[item].waitForExistence(timeout: 10))
    }

    func testAddBuyUndoAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let name = "Milk \(UUID().uuidString.prefix(8))"
        app.buttons["Add item"].tap()
        let field = app.textFields["What do you need?"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons["Add"].tap()

        let buy = app.buttons["Bought \(name)"]
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "Item should survive relaunch")

        buy.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 10))
        app.buttons["Undo"].tap()
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
    }

    func testEditQuantityCorrectPurchaseAndUndoFromHistory() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        let name = "Eggs \(UUID().uuidString.prefix(8))"
        app.buttons["Add item"].tap()
        let field = app.textFields["What do you need?"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons["Add"].tap()

        let editItem = app.buttons["Edit quantity for \(name)"]
        XCTAssertTrue(editItem.waitForExistence(timeout: 10))
        editItem.tap()
        let stepper = app.steppers["quantityStepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        stepper.buttons["quantityStepper-Increment"].tap()
        app.buttons["Save"].tap()
        app.swipeDown()
        capture("Shopping list with quantity", in: app)

        app.buttons["Bought \(name)"].tap()
        app.buttons["See all purchases"].tap()
        capture("Purchase history", in: app)
        let editPurchase = app.buttons["Edit purchased quantity for \(name)"]
        XCTAssertTrue(editPurchase.waitForExistence(timeout: 10))
        XCTAssertEqual(editPurchase.value as? String, "Quantity 2")
        editPurchase.tap()
        let purchaseStepper = app.steppers["quantityStepper"]
        XCTAssertTrue(purchaseStepper.waitForExistence(timeout: 10))
        purchaseStepper.buttons["quantityStepper-Increment"].tap()
        capture("Correcting a purchase", in: app)
        app.buttons["Save"].tap()
        XCTAssertEqual(editPurchase.value as? String, "Quantity 3")

        app.buttons["Undo purchase"].firstMatch.tap()
        XCTAssertFalse(editPurchase.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Bought \(name)"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["Edit quantity for \(name)"].value as? String, "Quantity 3")
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
