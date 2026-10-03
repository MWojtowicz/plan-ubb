import XCTest

/// Starts the Live Activity from Settings and checks it shows up on the lock screen.
/// It depends on the plan having classes left today and changes the simulator's lock screen,
/// so it only runs with RUN_LOCKSCREEN_TEST=1 (pass TEST_RUNNER_RUN_LOCKSCREEN_TEST=1 to xcodebuild).
final class LiveActivityTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LOCKSCREEN_TEST"] == "1")
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("activity-\(name).png"))
            try? springboard.debugDescription.write(toFile: "\(dir)/activity-\(name).txt", atomically: true, encoding: .utf8)
        }
    }

    func testLiveActivityOnLockScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestPlan", "142113", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Settings"].tap()

        let start = app.buttons["Start now"]
        let update = app.buttons["Update now"]
        if start.waitForExistence(timeout: 5) { start.tap() } else { update.tap() }
        try XCTSkipUnless(update.waitForExistence(timeout: 5), "No classes left today, so there's nothing to show.")
        capture("1-settings")

        XCUIDevice.shared.press(.home)
        sleep(2)
        capture("2-dynamic-island")

        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        XCUIDevice.shared.press(.home) // wake → lock screen
        sleep(3)
        capture("3-lockscreen")
        let banner = springboard.descendants(matching: .any)
                        // The banner's header: "NOW · LECTURE", "BREAK · NEXT CLASS IN", "FIRST CLASS IN" or "DONE FOR TODAY".
            .matching(NSPredicate(format: "label BEGINSWITH 'NOW ·' OR label ENDSWITH 'CLASS IN' OR label == 'DONE FOR TODAY'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Live Activity isn't on the lock screen")
    }
}
