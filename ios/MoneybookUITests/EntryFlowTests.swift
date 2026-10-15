import XCTest

/// Walks the Money Manager entry flow against a local server:
/// `-serverURL` / `-apiToken` come from the TEST_SERVER / TEST_TOKEN environment variables.
final class EntryFlowTests: XCTestCase {
    func testAddExpenseWithKeypad() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["TEST_SERVER"], let token = env["TEST_TOKEN"] else { throw XCTSkip("TEST_SERVER / TEST_TOKEN not set") }
        let app = XCUIApplication()
        app.launchArguments = ["-serverURL", server, "-apiToken", token, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["Add transaction"].tap()
        // The category panel opens first; pick one, then the keypad follows.
        let category = app.buttons["Transportasi"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        for key in ["1", "2", "3", "4", "5"] { app.buttons[key].tap() }
        app.buttons["Done"].tap()
        let note = app.textFields.firstMatch
        note.typeText("UI test entry")
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["UI test entry"].waitForExistence(timeout: 8))
    }

    /// Device locale (no en_US override), no category, keyboard dismissed with Return. This flow used to crash
    /// while the save animation resolved colours off the main thread.
    func testSaveWithoutCategory() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["TEST_SERVER"], let token = env["TEST_TOKEN"] else { throw XCTSkip("TEST_SERVER / TEST_TOKEN not set") }
        let app = XCUIApplication()
        app.launchArguments = ["-serverURL", server, "-apiToken", token]
        app.launch()

        app.buttons["Add transaction"].tap()
        XCTAssertTrue(app.buttons["Rp"].waitForExistence(timeout: 5))
        app.buttons["Rp"].firstMatch.tap()
        for key in ["2", "5", "0", "0", "0"] { app.buttons[key].tap() }
        app.buttons["Done"].tap()
        app.textFields.firstMatch.typeText("UI test no category\n")
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["UI test no category"].waitForExistence(timeout: 8))
    }
}
