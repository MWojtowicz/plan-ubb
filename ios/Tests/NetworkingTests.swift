import XCTest
@testable import PlanUbb

/// Answers requests from a queue of canned responses, counting how many were made.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var statuses: [Int] = []
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("BEGIN:VCALENDAR".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class NetworkingTests: XCTestCase {
    private var session: URLSession!
    private let url = URL(string: "https://plany.ubb.edu.pl/plan.php")!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.requests = 0
    }

    func testRetriesServerErrors() async throws {
        StubProtocol.statuses = [503, 502, 200]
        let text = try await session.planText(from: url)
        XCTAssertEqual(text, "BEGIN:VCALENDAR")
        XCTAssertEqual(StubProtocol.requests, 3)
    }

    func testGivesUpAfterThreeAttempts() async {
        StubProtocol.statuses = [503, 503, 503, 200]
        do {
            _ = try await session.planText(from: url)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(StubProtocol.requests, 3)
        }
    }

    func testDoesNotRetryClientErrors() async {
        StubProtocol.statuses = [404]
        do {
            _ = try await session.planText(from: url)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(StubProtocol.requests, 1)
        }
    }
}
