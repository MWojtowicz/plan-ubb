import XCTest
@testable import PlanUbb

/// Classes are shown in Polish time, whatever the device's time zone.
final class PlanTimeTests: XCTestCase {
    private var savedDefault: TimeZone!

    override func setUp() {
        savedDefault = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
    }

    override func tearDown() {
        NSTimeZone.default = savedDefault
    }

    /// Thursday 22 October 2026, 13:15 in Poland (11:15 UTC, 04:15 in Los Angeles).
    private let classStart = Date(timeIntervalSince1970: 1_792_667_700)

    func testTimeIsPolish() {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = Locale(identifier: "pl_PL")
        XCTAssertEqual(classStart.planFormatted(style), "13:15")
    }

    func testDayIsPolish() {
        // 00:30 on Friday in Poland is still Thursday in Los Angeles.
        let lateNight = Date(timeIntervalSince1970: 1_792_708_200)
        XCTAssertEqual(Calendar.plan.component(.weekday, from: lateNight), 6)
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.locale = Locale(identifier: "en_US")
        XCTAssertEqual(lateNight.planFormatted(style), "Friday")
    }

    func testWeekStartsOnPolishMonday() {
        let monday = Calendar.plan.startOfWeek(for: classStart)
        XCTAssertEqual(monday, Date(timeIntervalSince1970: 1_792_360_800))  // 19 Oct 2026 00:00 in Poland
    }
}
