import Foundation

// MARK: - ICS

struct RawICSEvent: Hashable {
    let start: Date
    let end: Date
    let summary: String
}

enum ICSParser {
    static func parse(_ text: String) -> [RawICSEvent] {
        var events: [RawICSEvent] = []
        var fields: [String: (params: [String: String], value: String)]?

        for line in unfoldedLines(text) {
            if line == "BEGIN:VEVENT" {
                fields = [:]
                continue
            }
            if line == "END:VEVENT" {
                if let f = fields,
                   let s = f["DTSTART"], let start = parseDate(s.value, params: s.params),
                   let e = f["DTEND"], let end = parseDate(e.value, params: e.params) {
                    events.append(RawICSEvent(start: start, end: end, summary: unescape(f["SUMMARY"]?.value ?? "")))
                }
                fields = nil
                continue
            }
            guard fields != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon].split(separator: ";").map(String.init)
            guard let name = head.first?.uppercased() else { continue }
            var params: [String: String] = [:]
            for p in head.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
            }
            fields?[name] = (params, String(line[line.index(after: colon)...]))
        }
        return events.sorted { $0.start < $1.start }
    }

    /// Joins several exports of the same plan, dropping events that appear in more than one.
    static func merge(_ exports: [[RawICSEvent]]) -> [RawICSEvent] {
        var seen = Set<RawICSEvent>()
        return exports.joined().filter { seen.insert($0).inserted }.sorted { $0.start < $1.start }
    }

    private static func unfoldedLines(_ text: String) -> [String] {
        var lines: [String] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    static func parseDate(_ value: String, params: [String: String] = [:]) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        if value.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else if value.contains("T") {
            f.timeZone = TimeZone(identifier: params["TZID"] ?? "Europe/Warsaw") ?? .warsaw
            f.dateFormat = "yyyyMMdd'T'HHmmss"
        } else {
            f.timeZone = .warsaw
            f.dateFormat = "yyyyMMdd"
        }
        return f.date(from: value)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - Summary ("Ak wyk MaBe L136", "JaI lek BGó ASzw L334A L324A")

struct ParsedSummary: Hashable {
    let subjectCode: String
    let kindCode: String
    let teacherCodes: [String]
    let rooms: [String]
}

enum SummaryParser {
    private static let roomPattern = try! NSRegularExpression(pattern: "^[A-Z]{1,3}\\d+[A-Za-z]?$")

    static func parse(_ summary: String, knownRooms: Set<String> = [], knownTeachers: Set<String> = []) -> ParsedSummary {
        let tokens = summary.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let subject = tokens.first else {
            return ParsedSummary(subjectCode: "", kindCode: "", teacherCodes: [], rooms: [])
        }
        var teachers: [String] = []
        var rooms: [String] = []
        for token in tokens.dropFirst(2) {
            if knownTeachers.contains(token) {
                teachers.append(token)
            } else if knownRooms.contains(token) || looksLikeRoom(token) {
                rooms.append(token)
            } else {
                teachers.append(token)
            }
        }
        return ParsedSummary(subjectCode: subject, kindCode: tokens.count > 1 ? tokens[1] : "", teacherCodes: teachers, rooms: rooms)
    }

    static func looksLikeRoom(_ token: String) -> Bool {
        roomPattern.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) != nil
    }
}

// MARK: - HTML plan page

struct WeekOption: Hashable {
    let id: Int
    /// Monday of the week, as "yyyy-MM-dd" in Europe/Warsaw.
    let mondayKey: String
}

struct PlanPage {
    var planName: String?
    var selectedWeekID: Int?
    var weeks: [WeekOption] = []
    var subjects: [String: String] = [:]
    var teacherIDs: [String: Int] = [:]
    var roomCodes: Set<String> = []
}

enum PlanHTMLParser {
    static func parse(_ html: String) -> PlanPage {
        var page = PlanPage()
        page.planName = planName(in: html)

        for m in matches("<strong>([^<]+)</strong>\\s*-\\s*([^<]+)", in: html) {
            var name = m[2]
            if let r = name.range(of: ", występowanie:") { name = String(name[..<r.lowerBound]) }
            page.subjects[decode(m[1]).trimmed] = decode(name).trimmed
        }
        for m in matches("type=10&(?:amp;)?id=(\\d+)\"[^>]*>([^<]+)</a>", in: html) {
            if let id = Int(m[1]) { page.teacherIDs[decode(m[2]).trimmed] = id }
        }
        for m in matches("type=20&(?:amp;)?id=\\d+\"[^>]*>([^<]+)</a>", in: html) {
            page.roomCodes.insert(decode(m[1]).trimmed)
        }

        // Week dropdown: <option value="788" selected>28.09-04.10
        let startYear = matches("rok (\\d{4})/(\\d{4})", in: html).first.flatMap { Int($0[1]) }
        if let startYear,
           let selectStart = html.range(of: "id=\"wBWeek\"") {
            let rest = html[selectStart.upperBound...]
            let select = rest.range(of: "</select>").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
            for m in matches("<option value=\"(\\d+)\"([^>]*)>\\s*(\\d{2})\\.(\\d{2})-\\d{2}\\.\\d{2}", in: select) {
                guard let id = Int(m[1]), let day = Int(m[3]), let month = Int(m[4]) else { continue }
                // Academic year: Aug–Dec belong to the first year, Jan–Jul to the second.
                let year = month >= 8 ? startYear : startYear + 1
                page.weeks.append(WeekOption(id: id, mondayKey: String(format: "%04d-%02d-%02d", year, month, day)))
                if m[2].contains("selected") { page.selectedWeekID = id }
            }
        }
        return page
    }

    /// "Plan zajęć - prof. UBB dr hab. inż. Andrzej Nowak, tydzień 28.09-04.10, …" → the name part.
    static func planName(in html: String) -> String? {
        matches("Plan zajęć - (.+?), (?:liczba stanowisk|tydzień)", in: html).first.map { decode($0[1]).trimmed }
    }

    static func mondayKey(for date: Date) -> String {
        var cal = Calendar.plan
        cal.timeZone = .warsaw
        let monday = cal.startOfWeek(for: date)
        let c = cal.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension TimeZone {
    static let warsaw = TimeZone(identifier: "Europe/Warsaw")!
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
