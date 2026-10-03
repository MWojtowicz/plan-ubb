import XCTest

/// Walks the first-launch group picker down to Inf/NZ/Ist/3sem/1gr/b against the live site.
final class GroupPickerUITests: XCTestCase {
    func testPicksGroupOnFirstLaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The checks below look for English labels.
        app.launchArguments = ["-UITestResetPlan", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose your group"].waitForExistence(timeout: 10))
        for step in ["Wydział Budowy Maszyn i Informatyki", "Niestacjonarne Zaoczne", "Informatyka NZ",
                     "I stopień", "Semester 3", "Group 1", "Subgroup b"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", step)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20), "No row \(step)")
            row.tap()
        }

        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Choose your group"].exists)

        // The choice sticks across launches.
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Choose your group"].exists)
    }
}
