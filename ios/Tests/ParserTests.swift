import XCTest

/// Fixtures are real responses captured from plany.ubb.edu.pl (plan id 142113, Oct 2026).
final class ParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "test-fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testICSParsesWholeSemester() throws {
        let events = ICSParser.parse(try fixture("plan.ics"))
        XCTAssertEqual(events.count, 96)
        XCTAssertEqual(events, events.sorted { $0.start < $1.start })

        let first = try XCTUnwrap(events.first { $0.summary == "Ak wyk MaBe L136" })
        // DTSTART:20261003T060000Z → 08:00 in Warsaw (CEST)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .warsaw
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: first.start)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 10, 3, 8, 0])
        XCTAssertEqual(first.end.timeIntervalSince(first.start), 90 * 60)
    }

    func testSummaryWithMultipleTeachersAndRooms() {
        let p = SummaryParser.parse("JaI lek BGó ASzw L334A L324A")
        XCTAssertEqual(p.subjectCode, "JaI")
        XCTAssertEqual(p.kindCode, "lek")
        XCTAssertEqual(p.teacherCodes, ["BGó", "ASzw"])
        XCTAssertEqual(p.rooms, ["L334A", "L324A"])
    }

    func testSummaryUsesKnownCodes() {
        let p = SummaryParser.parse("MdI ćw WWi L136", knownRooms: ["L136"], knownTeachers: ["WWi"])
        XCTAssertEqual(p.kindCode, "ćw")
        XCTAssertEqual(p.teacherCodes, ["WWi"])
        XCTAssertEqual(p.rooms, ["L136"])
    }

    func testWeekPage() throws {
        let page = PlanHTMLParser.parse(try fixture("week.html"))
        XCTAssertEqual(page.planName, "Inf/NZ/Ist/3sem/1gr/b")
        XCTAssertEqual(page.subjects["Ak"], "Architektura komputerów")
        XCTAssertEqual(page.subjects["SoII"], "Systemy operacyjne II")
        XCTAssertEqual(page.subjects.count, 8)
        XCTAssertEqual(page.teacherIDs["ANo"], 91148)
        XCTAssertEqual(page.teacherIDs["ASzw"], 7144)
        XCTAssertTrue(page.roomCodes.contains("L334A"))
        XCTAssertEqual(page.selectedWeekID, 788)
        XCTAssertTrue(page.weeks.contains(WeekOption(id: 788, mondayKey: "2026-09-28")))
        XCTAssertTrue(page.weeks.contains(WeekOption(id: 802, mondayKey: "2027-01-04")))
    }

    func testTeacherPageName() throws {
        XCTAssertEqual(PlanHTMLParser.planName(in: try fixture("teacher.html")), "prof. UBB dr hab. inż. Andrzej Nowak")
    }

    func testMondayKeyMatchesWeekOptions() throws {
        let events = ICSParser.parse(try fixture("plan.ics"))
        let first = try XCTUnwrap(events.first)
        XCTAssertEqual(PlanHTMLParser.mondayKey(for: first.start), "2026-09-28")
    }

    func testPlanSourceFromURL() {
        let s = PlanSource(string: "https://plany.ubb.edu.pl/plan.php?type=0&id=142113&winW=1319&winH=795&loadBG=000000")
        XCTAssertEqual(s, PlanSource(type: 0, id: 142113))
        XCTAssertEqual(PlanSource(string: " 91148 "), PlanSource(type: 0, id: 91148))
        XCTAssertEqual(PlanSource(string: "https://plany.ubb.edu.pl/plan.php?type=10&id=91148"), PlanSource(type: 10, id: 91148))
        XCTAssertNil(PlanSource(string: "hello"))
    }

    func testSnapshotQueries() {
        let now = Date()
        func event(_ startOffset: TimeInterval, _ minutes: Double) -> ClassEvent {
            ClassEvent(id: "\(startOffset)", start: now + startOffset, end: now + startOffset + minutes * 60,
                       subjectCode: "X", subjectName: "X", kindCode: "wyk", teacherCodes: [], teachers: [], rooms: [])
        }
        let running = event(-600, 90)
        let later = event(3600, 45)
        let snapshot = ScheduleSnapshot(source: .default, fetchedAt: now, events: [event(-7200, 30), running, later])
        XCTAssertEqual(snapshot.current(at: now), running)
        XCTAssertEqual(snapshot.upcoming(after: now), [later])
    }

    func testGroupTreeRoots() throws {
        let roots = PlanTreeParser.roots(in: try fixture("left_menu.html"))
        XCTAssertEqual(roots.count, 5)
        XCTAssertEqual(roots.first, PlanTreeNode(branchID: 6153, name: "Wydział Budowy Maszyn i Informatyki"))
        XCTAssertTrue(roots.contains { $0.name == "Wydział Inżynierii Materiałów, Budownictwa i Środowiska" })
    }

    func testGroupTreeLevels() throws {
        let courses = PlanTreeParser.children(in: try fixture("tree_courses.html"))
        XCTAssertEqual(courses.map(\.name), ["Cyberbezpieczeństwo NZ", "Informatyka NZ", "Sztuczna inteligencja NZ", "Zarządzanie i inżynieria produkcji NZ"])
        XCTAssertEqual(courses[1].branchID, 6970)
        XCTAssertNil(courses[1].plan)

        // Groups expand further and are plans themselves.
        let groups = PlanTreeParser.children(in: try fixture("tree_groups.html"))
        XCTAssertEqual(groups, [
            PlanTreeNode(branchID: 110206, name: "Inf/NZ/Ist/3sem/1gr", plan: PlanSource(type: 2, id: 110206)),
            PlanTreeNode(branchID: 112225, name: "Inf/NZ/Ist/3sem/2gr", plan: PlanSource(type: 2, id: 112225)),
        ])
        XCTAssertEqual(groups.map { $0.shortName(among: groups) }, ["Group 1", "Group 2"])

        let subgroups = PlanTreeParser.children(in: try fixture("tree_subgroups.html"))
        XCTAssertEqual(subgroups.map(\.plan), [PlanSource(type: 0, id: 8145), PlanSource(type: 0, id: 142113)])
        XCTAssertTrue(subgroups.allSatisfy(\.isLeaf))
        XCTAssertEqual(subgroups.map { $0.shortName(among: subgroups) }, ["Subgroup a", "Subgroup b"])
    }

    func testGroupTreeShortNames() {
        func node(_ name: String) -> PlanTreeNode { PlanTreeNode(branchID: 1, name: name) }
        let semesters = [node("Inf/NZ/Ist/1sem"), node("Inf/NZ/Ist/2sem")]
        XCTAssertEqual(semesters.map { $0.shortName(among: semesters) }, ["Semester 1", "Semester 2"])
        let degrees = [node("Inf/NZ/ I stopień"), node("Inf/NZ/ II stopień")]
        XCTAssertEqual(degrees.map { $0.shortName(among: degrees) }, ["I stopień", "II stopień"])
        let only = node("Inf/NZ/Ist/3sem/1gr")
        XCTAssertEqual(only.shortName(among: [only]), "Group 1")
        XCTAssertEqual(node("Stacjonarne").shortName(among: [node("Stacjonarne"), node("Niestacjonarne Zaoczne")]), "Stacjonarne")
    }

    func testLiveActivityPhases() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .warsaw
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 0)))
        func at(_ h: Int, _ m: Int) -> Date { day.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }
        func event(_ h: Int, _ m: Int, _ minutes: Double, _ code: String) -> ClassEvent {
            ClassEvent(id: code, start: at(h, m), end: at(h, m) + minutes * 60, subjectCode: code, subjectName: code,
                       kindCode: "wyk", teacherCodes: [], teachers: [], rooms: [])
        }
        let snapshot = ScheduleSnapshot(source: .default, fetchedAt: day, events: [
            event(8, 0, 90, "A"), event(9, 45, 90, "B"), event(24 + 10, 0, 30, "Tomorrow"),
        ])

        let state = try XCTUnwrap(ClassActivityAttributes.ContentState(snapshot: snapshot, at: at(7, 0), calendar: cal))
        XCTAssertEqual(state.classes.map(\.code), ["A", "B"])
        XCTAssertEqual(state.dayRange, at(8, 0)...at(11, 15))

        guard case .waiting(let first, nil) = state.phase(at: at(7, 0)) else { return XCTFail("before first class") }
        XCTAssertEqual(first.code, "A")
        guard case .inClass(let a, let next) = state.phase(at: at(8, 30)) else { return XCTFail("in class") }
        XCTAssertEqual([a.code, next?.code], ["A", "B"])
        guard case .waiting(let b, let since) = state.phase(at: at(9, 35)) else { return XCTFail("break") }
        XCTAssertEqual(b.code, "B")
        XCTAssertEqual(since, at(9, 30))
        guard case .done = state.phase(at: at(12, 0)) else { return XCTFail("after last class") }

        XCTAssertEqual(state.nextBoundary(after: at(8, 30)), at(9, 30))
        XCTAssertNil(state.nextBoundary(after: at(11, 15)))
        XCTAssertNil(ClassActivityAttributes.ContentState(snapshot: snapshot, at: at(11, 15), calendar: cal))
    }

    func testLiveActivityPayloadFitsActivityKitLimit() throws {
        let events = ICSParser.parse(try fixture("plan.ics")).map { e in
            ClassEvent(id: e.summary, start: e.start, end: e.end, subjectCode: "Subject", subjectName: String(repeating: "Long subject name ", count: 6),
                       kindCode: "wyk", teacherCodes: [], teachers: [String(repeating: "prof. dr hab. inż. ", count: 4)], rooms: ["L334A", "L324A"])
        }
        // Squash the semester into one day to get an absurdly long day.
        let day = try XCTUnwrap(events.first).start
        let crowded = events.prefix(40).enumerated().map { i, e in e.withStart(day.addingTimeInterval(TimeInterval(i * 600))) }
        let snapshot = ScheduleSnapshot(source: .default, fetchedAt: day, events: crowded)
        let state = try XCTUnwrap(ClassActivityAttributes.ContentState(snapshot: snapshot, at: day))
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4096)
        XCTAssertFalse(state.classes.isEmpty)
    }
}

private extension ClassEvent {
    func withStart(_ start: Date) -> ClassEvent {
        ClassEvent(id: id, start: start, end: start + duration, subjectCode: subjectCode, subjectName: subjectName,
                   kindCode: kindCode, teacherCodes: teacherCodes, teachers: teachers, rooms: rooms)
    }
}
