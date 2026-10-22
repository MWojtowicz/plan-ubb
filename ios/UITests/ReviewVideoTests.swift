import XCTest

/// Walks through the app at a viewing pace for an App Review screen recording, started beforehand with
/// `xcrun simctl io <device> recordVideo`. Install the app fresh first, so the group picker shows.
/// Runs only with REVIEW_VIDEO=1 (pass TEST_RUNNER_REVIEW_VIDEO=1 to xcodebuild).
final class ReviewVideoTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REVIEW_VIDEO"] == "1")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func tap(_ label: String, beginsWith: Bool = false, timeout: TimeInterval = 30) {
        let format = beginsWith ? "label BEGINSWITH %@" : "label == %@"
        let button = app.buttons.matching(NSPredicate(format: format, label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "No button \(label)")
        button.tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Class rows are buttons labelled "8:00 AM, 9:30 AM, Subject, …" (or "08:00, …").
    private var classRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{1,2}:[0-9]{2}.*"))
    }

    func testReviewWalkthrough() {
        // Start on the Home Screen, so the recording begins with the launch. The first press
        // wakes a locked simulator, the second unlocks it (no passcode).
        XCUIDevice.shared.press(.home)
        pause(1)
        XCUIDevice.shared.press(.home)
        pause(3)
        app.launchArguments = ["-UITestResetPlan", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // First screen: the intro with the "unofficial app, public data" notice.
        XCTAssertTrue(app.staticTexts["Choose your group"].waitForExistence(timeout: 20))
        pause(4)
        for step in ["Wydział Budowy Maszyn i Informatyki", "Stacjonarne", "Informatyka S",
                     "I stopień", "Semester 3", "Group 1", "Subgroup a"] {
            tap(step, beginsWith: true)
            pause(1.5)
        }

        // Upcoming: the class now, the next ones, and a class's details.
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 30))
        XCTAssertTrue(classRows.firstMatch.waitForExistence(timeout: 60), "The plan didn't load")
        pause(4)
        app.swipeUp(velocity: .slow)
        pause(2)
        app.swipeDown(velocity: .slow)
        pause(1.5)
        classRows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["When"].waitForExistence(timeout: 5))
        pause(3.5)
        goBack()
        pause(1.5)

        // Week: this week, the next one, and back.
        tap("Week")
        pause(3)
        app.swipeLeft()
        pause(2.5)
        app.swipeRight()
        pause(2)
        classRows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["When"].waitForExistence(timeout: 5))
        pause(3)
        goBack()
        pause(1.5)

        // Settings: changing the group, the Live Activity switch, About and the privacy policy.
        tap("Settings")
        pause(3)
        tap("Change group…")
        pause(2.5)
        tap("Cancel")
        pause(1.5)
        app.swipeUp(velocity: .slow)
        pause(1)
        app.swipeUp(velocity: .slow)
        pause(5)
        // A SwiftUI Link is exposed as a link, not a button.
        let privacy = app.links.matching(NSPredicate(format: "label BEGINSWITH %@", "Privacy policy")).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "No Privacy policy link")
        privacy.tap()
        pause(6)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        pause(2)

        // The Live Activity on the Lock Screen.
        tap("Upcoming")
        pause(2)
        XCUIDevice.shared.press(.home)
        pause(2)
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        pause(2)
        XCUIDevice.shared.press(.home)  // wake → Lock Screen
        pause(6)
        XCUIDevice.shared.press(.home)  // unlock, so the next run doesn't start locked
        pause(1)
    }
}
