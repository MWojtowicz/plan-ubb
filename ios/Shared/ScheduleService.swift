import Foundation

enum ScheduleError: LocalizedError {
    case badResponse(Int)
    case notACalendar
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return String(localized: "The plan server responded with HTTP \(code).")
        case .notACalendar: return String(localized: "The plan server did not return a calendar. Check the plan URL in Settings.")
        case .unexpectedResponse: return String(localized: "The plan server sent an unexpected response. Try again later.")
        }
    }
}

extension URLSession {
    /// GETs `url` as text. The plan server is sometimes slow or briefly unavailable (more so from
    /// abroad), so timeouts, dropped connections and 5xx/429 responses are retried after 1 s and 2 s.
    func planText(from url: URL, attempts: Int = 3) async throws -> String {
        var attempt = 1
        while true {
            do {
                var request = URLRequest(url: url, timeoutInterval: 30)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw ScheduleError.badResponse(http.statusCode)
                }
                return String(decoding: data, as: UTF8.self)
            } catch {
                guard attempt < attempts, Self.isTransient(error) else { throw error }
                try await Task.sleep(for: .seconds(attempt))
                attempt += 1
            }
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        switch error {
        case ScheduleError.badResponse(let code):
            return code == 429 || code >= 500
        case let error as URLError:
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                    .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed].contains(error.code)
        default:
            return false
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

        async let icsText = export(source)
        async let mainHTML = get(pageQuery(type: source.type, id: source.id))

        // In a week without classes the export is the plan's "Brak zajęć" HTML page instead of a
        // calendar. That page still names the plan and lists the semester's weeks; for a wrong plan id
        // the name is empty.
        let ics = try await icsText
        let emptyWeekPage = ics.contains("BEGIN:VCALENDAR") ? nil : PlanHTMLParser.parse(ics)
        if let emptyWeekPage, emptyWeekPage.planName == nil { throw ScheduleError.notACalendar }

        // The HTML page adds names, and the week list when the export had none to give; a failure
        // there must not lose the classes.
        let mainPage: PlanPage
        var mainPageError: Error?
        do {
            mainPage = PlanHTMLParser.parse(try await mainHTML)
        } catch {
            mainPage = PlanPage()
            mainPageError = error
        }
        directory.merge(mainPage)
        let weekList = mainPage.weeks.isEmpty ? emptyWeekPage ?? mainPage : mainPage

        // The export only has the classes held in the current week's pattern: in an odd week,
        // classes held in even weeks only ("NZ-P") are missing, and in a week without classes
        // there are none. The export for each other week fills them in.
        let otherWeeks = weekList.weeks.map(\.id).filter { $0 != weekList.selectedWeekID }
        let weekExports = await fetchAll(otherWeeks) { id in
            ICSParser.parse(try await export(source, week: id))
        }
        let rawEvents = ICSParser.merge([ICSParser.parse(ics)] + weekExports.compactMap { try? $0.get() })

        // No classes at all is a real answer (an even semester in autumn has none yet), but only
        // when every week was checked. Otherwise report what went wrong.
        if rawEvents.isEmpty {
            for case .failure(let error) in weekExports { throw error }
            if weekList.weeks.isEmpty, let mainPageError { throw mainPageError }
        }

        // Weekly pages for weeks containing subjects/teachers we can't name yet.
        let weekIDs = Dictionary(weekList.weeks.map { ($0.mondayKey, $0.id) }, uniquingKeysWith: { a, _ in a })
        var weeksToFetch = Set<Int>()
        for raw in rawEvents {
            let parsed = SummaryParser.parse(raw.summary, knownRooms: directory.rooms, knownTeachers: Set(directory.teacherIDs.keys))
            let missing = directory.subjects[parsed.subjectCode] == nil
                || parsed.teacherCodes.contains { directory.teacherIDs[$0] == nil }
            if missing, let id = weekIDs[PlanHTMLParser.mondayKey(for: raw.start)], id != mainPage.selectedWeekID {
                weeksToFetch.insert(id)
            }
        }
        for case .success(let page) in await fetchAll(Array(weeksToFetch), { id in
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
        for case .success(let (code, name)?) in await fetchAll(unnamed, { code, id -> (String, String)? in
            guard let name = PlanHTMLParser.planName(in: try await get(pageQuery(type: 10, id: id))) else { return nil }
            return (code, name)
        }) {
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

        let snapshot = ScheduleSnapshot(source: source, planName: mainPage.planName ?? emptyWeekPage?.planName, fetchedAt: Date(), events: events)
        return (snapshot, directory)
    }

    // MARK: - Networking

    private func pageQuery(type: Int, id: Int, week: Int? = nil) -> [String: Any] {
        // Without winW/winH the server returns a JS stub that measures the window.
        var q: [String: Any] = ["type": type, "id": id, "winW": 1319, "winH": 795, "loadBG": "000000"]
        if let week { q["w"] = week }
        return q
    }

    /// The ICS export, or for a week without classes the plan's "Brak zajęć" page. Anything else (an error
    /// or maintenance page sent with HTTP 200) is retried after 1 s and 2 s, then reported as unexpected.
    private func export(_ source: PlanSource, week: Int? = nil, attempts: Int = 3) async throws -> String {
        var query: [String: Any] = ["type": source.type, "id": source.id, "cvsfile": "true"]
        if let week { query["w"] = week }
        var attempt = 1
        while true {
            let text = try await get(query)
            if text.contains("BEGIN:VCALENDAR") || PlanHTMLParser.isPlanPage(text) { return text }
            guard attempt < attempts else { throw ScheduleError.unexpectedResponse }
            try await Task.sleep(for: .seconds(attempt))
            attempt += 1
        }
    }

    private func get(_ query: [String: Any]) async throws -> String {
        var comps = URLComponents(string: Self.base)!
        comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        return try await session.planText(from: comps.url!)
    }

    /// Runs `work` for every input, at most `limit` at a time so a slow server isn't flooded.
    private func fetchAll<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        limit: Int = 4,
        _ work: @escaping @Sendable (Input) async throws -> Output
    ) async -> [Result<Output, Error>] {
        await withTaskGroup(of: Result<Output, Error>.self) { group in
            var pending = inputs.makeIterator()
            func startNext() {
                guard let input = pending.next() else { return }
                group.addTask {
                    do { return .success(try await work(input)) } catch { return .failure(error) }
                }
            }
            for _ in 0..<limit { startNext() }
            var results: [Result<Output, Error>] = []
            for await result in group {
                results.append(result)
                startNext()
            }
            return results
        }
    }
}
