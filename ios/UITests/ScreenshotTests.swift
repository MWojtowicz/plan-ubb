import XCTest

/// Takes the README screenshots: Upcoming, Week and a class's details.
/// Runs only when TEST_RUNNER_SCREENSHOT_DIR is set; see `docs/screenshots/frame.py`.
final class ScreenshotTests: XCTestCase {
    func testReadmeScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_SCREENSHOT_DIR to take the README screenshots")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITestPlan", "142113", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 20))
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{1,2}:[0-9]{2}.*")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The plan didn't load")

        func snap(_ name: String) throws {
            sleep(1)  // Let animations settle.
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }

        try snap("ios-upcoming")

        app.buttons.matching(NSPredicate(format: "label == %@", "Week")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Week"].waitForExistence(timeout: 5))
        try snap("ios-week")

        app.buttons.matching(NSPredicate(format: "label == %@", "Upcoming")).firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["When"].waitForExistence(timeout: 5))
        try snap("ios-details")
    }
}
