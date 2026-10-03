import XCTest

final class AppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITestPlan", "142113", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 20))
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Saves a screenshot to $SCREENSHOT_DIR (set via TEST_RUNNER_SCREENSHOT_DIR) and attaches it.
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private var failures = 0

    override func record(_ issue: XCTIssue) {
        failures += 1
        let test = name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
        snap("FAIL-\(test)-\(failures)")
        dumpHierarchy("FAIL-\(test)-\(failures)")
        super.record(issue)
    }

    private func dumpHierarchy(_ name: String) {
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? app.debugDescription.write(toFile: dir + "/\(name).txt", atomically: true, encoding: .utf8)
        }
    }

    private func tab(_ name: String) {
        // iOS 26+ floating tab bars aren't always exposed as a TabBar element.
        let button = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No tab button \(name)")
        button.tap()
    }

    /// Every tab must still react to taps and scrolling.
    private func assertResponsive(_ context: String) {
        tab("Week")
        XCTAssertTrue(app.navigationBars["Week"].waitForExistence(timeout: 5), "Week tab didn't open \(context)")
        // Class rows are buttons labelled "08:00, 09:30, Subject, …".
        let rows = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{2}:[0-9]{2}, .*"))
        if rows.count > 3 {
            let row = rows.element(boundBy: 0)
            let before = row.frame
            app.swipeUp()
            XCTAssertNotEqual(row.exists ? row.frame : .zero, before, "Week list didn't scroll \(context)")
            app.swipeDown()
        }
        tab("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings tab didn't open \(context)")
        tab("Upcoming")
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 5), "Upcoming tab didn't open \(context)")
        let cell = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{2}:[0-9]{2}, .*")).firstMatch
        if cell.waitForExistence(timeout: 3) {
            cell.tap()
            XCTAssertTrue(app.staticTexts["When"].waitForExistence(timeout: 5), "Detail didn't open \(context)")
            // Back via the edge-swipe gesture.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
            XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 5), "Couldn't go back \(context)")
        }
    }

    func testStaysResponsiveAfterLockAndUnlock() {
        assertResponsive("before locking")
        tab("Week")
        snap("1-before-lock")

        let device = XCUIDevice.shared
        let lock = NSSelectorFromString("pressLockButton")
        XCTAssertTrue(device.responds(to: lock))
        device.perform(lock)
        sleep(2)
        device.press(.home)   // wake
        sleep(1)
        device.press(.home)   // unlock (no passcode on the simulator)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(1)
        snap("2-after-unlock")

        assertResponsive("after unlocking")
        snap("3-after-unlock-interaction")
    }

    func testStaysResponsiveAfterBackgrounding() {
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        assertResponsive("after returning from background")
    }

    func testRotation() {
        snap("rot-upcoming-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        snap("rot-upcoming-landscape")
        tab("Week")
        sleep(1)
        snap("rot-week-landscape")
        tab("Settings")
        sleep(1)
        snap("rot-settings-landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        tab("Week")
        sleep(1)
        snap("rot-week-portrait-after")
        assertResponsive("after rotating")
    }
}
