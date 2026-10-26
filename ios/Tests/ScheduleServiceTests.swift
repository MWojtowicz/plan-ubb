import XCTest
@testable import PlanUbb

/// Answers each request with `handler`, which gets the request's query items.
final class RouteProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ([String: String]) -> (status: Int, body: String) = { _ in (404, "") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let (status, body) = Self.handler(Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a }))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Fixtures: plan 142113 in the week of 26.10 (no classes), whose export is the "Brak zajęć" page
/// (plan_empty_week.html); its odd and even weeks' exports (plan.ics, plan_week790.ics); and the
/// page a wrong plan id gets (plan_unknown.html). 404s aren't retried, so failures stay fast.
final class ScheduleServiceTests: XCTestCase {
    private var service: ScheduleService!
    private let source = PlanSource(type: 0, id: 142113)

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RouteProtocol.self]
        service = ScheduleService(session: URLSession(configuration: config))
    }

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "test-fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// What App Review saw: the current week has no classes and the plan page didn't load.
    /// The empty week's page still lists the weeks, so the other weeks' exports give the plan.
    func testEmptyWeekWithoutPlanPage() async throws {
        let empty = try fixture("plan_empty_week.html")
        let odd = try fixture("plan.ics")
        let even = try fixture("plan_week790.ics")
        RouteProtocol.handler = { q in
            guard q["cvsfile"] != nil else { return (404, "") }
            switch q["w"] {
            case "790": return (200, even)
            case "793": return (200, odd)
            default: return (200, empty)
            }
        }
        let (snapshot, _) = try await service.fetch(source: source, directory: NameDirectory())
        XCTAssertEqual(snapshot.events.count, 100)
        XCTAssertEqual(snapshot.planName, "Inf/NZ/Ist/3sem/1gr/b")
    }

    /// An even semester in autumn: the plan exists but has no classes in any week.
    func testPlanWithoutClassesIsNotAnError() async throws {
        let empty = try fixture("plan_empty_week.html")
        RouteProtocol.handler = { _ in (200, empty) }
        let (snapshot, _) = try await service.fetch(source: source, directory: NameDirectory())
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertEqual(snapshot.planName, "Inf/NZ/Ist/3sem/1gr/b")
    }

    func testUnknownPlan() async throws {
        let unknown = try fixture("plan_unknown.html")
        RouteProtocol.handler = { _ in (200, unknown) }
        do {
            _ = try await service.fetch(source: PlanSource(type: 0, id: 999999999), directory: NameDirectory())
            XCTFail("Expected an error")
        } catch ScheduleError.notACalendar {
        }
    }

    /// When the other weeks can't be downloaded, the empty result says why instead of
    /// claiming the plan has no classes or a wrong URL.
    func testFailedWeeksAreReported() async throws {
        let empty = try fixture("plan_empty_week.html")
        RouteProtocol.handler = { q in q["w"] == nil ? (200, empty) : (404, "") }
        do {
            _ = try await service.fetch(source: source, directory: NameDirectory())
            XCTFail("Expected an error")
        } catch ScheduleError.badResponse(let code) {
            XCTAssertEqual(code, 404)
        }
    }

    func testUnknownPlanHasNoName() throws {
        XCTAssertNil(PlanHTMLParser.planName(in: try fixture("plan_unknown.html")))
        let page = PlanHTMLParser.parse(try fixture("plan_empty_week.html"))
        XCTAssertEqual(page.selectedWeekID, 792)
        XCTAssertEqual(page.weeks.count, 19)
    }

    func testStudyTerms() {
        XCTAssertEqual(StudyTerm.usual(forPlanNamed: "Inf/NZ/Ist/3sem/1gr/b"), .winter)
        XCTAssertEqual(StudyTerm.usual(forPlanNamed: "Inf/NZ/Ist/2sem"), .summer)
        XCTAssertEqual(StudyTerm.usual(forPlanNamed: "Inf/NZ/IIst/1sem/1gr"), .winter)
        XCTAssertNil(StudyTerm.usual(forPlanNamed: "prof. UBB dr hab. inż. Andrzej Nowak"))

        func date(_ month: Int) -> Date { Calendar.plan.date(from: DateComponents(year: 2026, month: month, day: 15))! }
        XCTAssertEqual(StudyTerm.current(at: date(10)), .winter)
        XCTAssertEqual(StudyTerm.current(at: date(1)), .winter)
        XCTAssertEqual(StudyTerm.current(at: date(3)), .summer)
        XCTAssertEqual(StudyTerm.current(at: date(8)), .winter)
    }
}
