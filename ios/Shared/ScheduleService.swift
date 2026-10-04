import Foundation

enum ScheduleError: LocalizedError {
    case badResponse(Int)
    case notACalendar

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return String(localized: "The plan server responded with HTTP \(code).")
        case .notACalendar: return String(localized: "The plan server did not return a calendar. Check the plan URL in Settings.")
        }
    }
}

/// Downloads a plan from plany.ubb.edu.pl.
///
/// Events come from the ICS exports (whole semester, abbreviated names). Full subject
/// names are taken from the legend on the weekly HTML pages, full teacher names from
/// each teacher's own plan page. Name lookups are cached in `NameDirectory`.
struct ScheduleService {
    private static let base = "https://plany.ubb.edu.pl/plan.php"
    var session: URLSession = .shared

    func fetch(source: PlanSource, directory: NameDirectory) async throws -> (ScheduleSnapshot, NameDirectory) {
        var directory = directory

        async let icsText = get(["type": source.type, "id": source.id, "cvsfile": "true"])
        async let mainHTML = get(pageQuery(type: source.type, id: source.id))

        let ics = try await icsText
        guard ics.contains("BEGIN:VCALENDAR") else { throw ScheduleError.notACalendar }

        // The HTML page only adds names; a failure there must not lose the schedule.
        let mainPage = (try? await mainHTML).map(PlanHTMLParser.parse) ?? PlanPage()
        directory.merge(mainPage)

        // The export only has the classes held in the current week's pattern: in an odd week,
        // classes held in even weeks only ("NZ-P") are missing. The export for each other week
        // fills them in.
        let otherWeeks = mainPage.weeks.map(\.id).filter { $0 != mainPage.selectedWeekID }
        let weekExports = await fetchAll(otherWeeks) { id in
            ICSParser.parse(try await get(["type": source.type, "id": source.id, "cvsfile": "true", "w": id]))
        }
        let rawEvents = ICSParser.merge([ICSParser.parse(ics)] + weekExports)

        // Weekly pages for weeks containing subjects/teachers we can't name yet.
        let weekIDs = Dictionary(mainPage.weeks.map { ($0.mondayKey, $0.id) }, uniquingKeysWith: { a, _ in a })
        var weeksToFetch = Set<Int>()
        for raw in rawEvents {
            let parsed = SummaryParser.parse(raw.summary, knownRooms: directory.rooms, knownTeachers: Set(directory.teacherIDs.keys))
            let missing = directory.subjects[parsed.subjectCode] == nil
                || parsed.teacherCodes.contains { directory.teacherIDs[$0] == nil }
            if missing, let id = weekIDs[PlanHTMLParser.mondayKey(for: raw.start)], id != mainPage.selectedWeekID {
                weeksToFetch.insert(id)
            }
        }
        for page in await fetchAll(Array(weeksToFetch), { id in
            PlanHTMLParser.parse(try await get(pageQuery(type: source.type, id: source.id, week: id)))
        }) {
            directory.merge(page)
        }

        // Teacher full names.
        let knownTeachers = Set(directory.teacherIDs.keys)
        let teacherCodes = Set(rawEvents.flatMap {
            SummaryParser.parse($0.summary, knownRooms: directory.rooms, knownTeachers: knownTeachers).teacherCodes
        })
        let unnamed = teacherCodes.filter { directory.teachers[$0] == nil }.compactMap { code in
            directory.teacherIDs[code].map { (code, $0) }
        }
        for (code, name) in await fetchAll(unnamed, { code, id -> (String, String)? in
            guard let name = PlanHTMLParser.planName(in: try await get(pageQuery(type: 10, id: id))) else { return nil }
            return (code, name)
        }).compactMap({ $0 }) {
            directory.teachers[code] = name
        }

        let events = rawEvents.map { raw -> ClassEvent in
            let p = SummaryParser.parse(raw.summary, knownRooms: directory.rooms, knownTeachers: knownTeachers)
            return ClassEvent(
                id: "\(Int(raw.start.timeIntervalSince1970))-\(raw.summary)",
                start: raw.start,
                end: raw.end,
                subjectCode: p.subjectCode,
                subjectName: directory.subjects[p.subjectCode] ?? p.subjectCode,
                kindCode: p.kindCode,
                teacherCodes: p.teacherCodes,
                teachers: p.teacherCodes.map { directory.teachers[$0] ?? $0 },
                rooms: p.rooms
            )
        }

        let snapshot = ScheduleSnapshot(source: source, planName: mainPage.planName, fetchedAt: Date(), events: events)
        return (snapshot, directory)
    }

    // MARK: - Networking

    private func pageQuery(type: Int, id: Int, week: Int? = nil) -> [String: Any] {
        // Without winW/winH the server returns a JS stub that measures the window.
        var q: [String: Any] = ["type": type, "id": id, "winW": 1319, "winH": 795, "loadBG": "000000"]
        if let week { q["w"] = week }
        return q
    }

    private func get(_ query: [String: Any]) async throws -> String {
        var comps = URLComponents(string: Self.base)!
        comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        var request = URLRequest(url: comps.url!, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ScheduleError.badResponse(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs `work` for every input concurrently, dropping failures.
    private func fetchAll<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        _ work: @escaping @Sendable (Input) async throws -> Output
    ) async -> [Output] {
        await withTaskGroup(of: Output?.self) { group in
            for input in inputs {
                group.addTask { try? await work(input) }
            }
            var results: [Output] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }
}
