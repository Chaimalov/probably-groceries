import XCTest

final class ProbablyGroceriesUITests: XCTestCase {
    func testAddBuyUndoAndPersistence() {
        let app = XCUIApplication()
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
}
