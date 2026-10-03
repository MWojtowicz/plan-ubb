import XCTest

/// Opens SpringBoard's lock screen editor and checks Plan UBB is in the widget gallery with rendered previews.
/// Changes the simulator's lock screen, so it only runs with RUN_LOCKSCREEN_TEST=1
/// (pass TEST_RUNNER_RUN_LOCKSCREEN_TEST=1 to xcodebuild).
final class LockScreenWidgetTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var step = 0

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LOCKSCREEN_TEST"] == "1")
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        step += 1
        let label = String(format: "lock-%02d-%@", step, name)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(label).png"))
            try? springboard.debugDescription.write(toFile: "\(dir)/\(label).txt", atomically: true, encoding: .utf8)
        }
    }

    private func tapFirst(_ labels: [String], timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                // SpringBoard often exposes the same control twice; tap the first visible copy.
                let matches = springboard.descendants(matching: .any)
                    .matching(NSPredicate(format: "label ==[c] %@ OR identifier ==[c] %@", label, label))
                for i in 0..<matches.count {
                    let element = matches.element(boundBy: i)
                    if element.exists && !element.frame.isEmpty {
                        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        return true
                    }
                }
            }
            usleep(300_000)
        } while Date() < deadline
        return false
    }

    func testWidgetIsInLockScreenGallery() {
        // Make sure the app ran once so the widget has data.
        let app = XCUIApplication()
        app.launchArguments = ["-UITestPlan", "142113", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 20))

        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        XCUIDevice.shared.press(.home) // wake → lock screen
        sleep(2)
        capture("lockscreen")

        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.6)
        sleep(2)
        capture("after-long-press")

        XCTAssertTrue(tapFirst(["Customize", "Customise"]), "No Customize button")
        sleep(2)
        capture("customize")

        _ = tapFirst(["Lock Screen"], timeout: 3)
        sleep(2)
        capture("editing")

        XCTAssertTrue(tapFirst(["grouped-widgets-reticle-view", "Add Widgets", "Add Widget"]), "No widget area")
        sleep(2)
        capture("gallery")

        // Find our app in the gallery (search, then list).
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Plan")
            sleep(2)
            capture("search")
        }
        // The gallery is a lazily loaded alphabetical list in a sheet: scroll until our app shows up.
        let entry = springboard.cells.matching(NSPredicate(format: "label ==[c] %@", "Plan UBB")).firstMatch
        for _ in 0..<8 where !(entry.exists && entry.isHittable) {
            springboard.cells.firstMatch.swipeUp()
            usleep(600_000)
        }
        capture("gallery-scrolled")
        let found = entry.exists
        if found { entry.tap(); sleep(2) }
        capture(found ? "plan-ubb-opened" : "plan-ubb-missing")
        XCTAssertTrue(found, "Plan UBB not listed in the lock screen widget gallery")

        // The widget's previews (circular + rectangular) are now on screen; check they show content.
        let preview = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Next", "No upcoming")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Widget preview didn't render")

        // Leave the lock screen as it was.
        _ = tapFirst(["Close"], timeout: 3)
        sleep(1)
        _ = tapFirst(["editing-cancel", "Cancel"], timeout: 3)
        sleep(1)
        // Leaving the editor can land in the wallpaper switcher: pick the current one, then unlock.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(1)
        capture("cleaned-up")
    }
}
