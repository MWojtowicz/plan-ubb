import Foundation

/// Identifies a plan on plany.ubb.edu.pl (`plan.php?type=…&id=…`).
/// type 0 = student group, 10 = teacher, 20 = room.
struct PlanSource: Codable, Hashable {
    var type: Int
    var id: Int

    static let `default` = PlanSource(type: 0, id: 142113)

    init(type: Int, id: Int) {
        self.type = type
        self.id = id
    }

    /// Accepts a full plan URL (as copied from the browser) or a bare numeric id.
    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) {
            self.init(type: 0, id: id)
            return
        }
        guard let items = URLComponents(string: trimmed)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value.flatMap(Int.init)
        else { return nil }
        let type = items.first(where: { $0.name == "type" })?.value.flatMap(Int.init) ?? 0
        self.init(type: type, id: id)
    }

    var webURL: URL {
        URL(string: "https://plany.ubb.edu.pl/plan.php?type=\(type)&id=\(id)&winW=1319&winH=795&loadBG=000000")!
    }
}

struct ClassEvent: Codable, Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let subjectCode: String
    var subjectName: String
    let kindCode: String
    let teacherCodes: [String]
    var teachers: [String]
    let rooms: [String]

    var kindName: String { ClassEvent.kindName(for: kindCode) }
    var location: String { rooms.isEmpty ? "—" : rooms.joined(separator: ", ") }
    var teacherNames: String { teachers.isEmpty ? "—" : teachers.joined(separator: ", ") }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    func isRunning(at date: Date) -> Bool { start <= date && date < end }

    static func kindName(for code: String) -> String {
        switch code.lowercased() {
        case "wyk": return String(localized: "Lecture")
        case "lab": return String(localized: "Laboratory")
        case "ćw", "cw": return String(localized: "Exercises")
        case "lek": return String(localized: "Language class")
        case "proj", "pro": return String(localized: "Project")
        case "sem": return String(localized: "Seminar")
        case "wf": return String(localized: "Physical education")
        case "": return String(localized: "Class")
        default: return code
        }
    }
}

struct ScheduleSnapshot: Codable {
    var source: PlanSource
    var planName: String?
    var fetchedAt: Date
    /// Sorted by start date.
    var events: [ClassEvent]

    func current(at date: Date) -> ClassEvent? {
        events.first { $0.isRunning(at: date) }
    }

    func upcoming(after date: Date, limit: Int = .max) -> [ClassEvent] {
        Array(events.lazy.filter { $0.start > date }.prefix(limit))
    }

    func events(from start: Date, to end: Date) -> [ClassEvent] {
        events.filter { $0.start >= start && $0.start < end }
    }
}

/// The two halves of the academic year. Odd semesters (1, 3, 5…) usually have their classes in the
/// winter term (October–January), even ones in the summer term (February–June). Plans are published
/// shortly before each term, so the other term's semesters have no classes yet.
enum StudyTerm {
    case winter, summer

    /// The term in progress or, between terms, the next one.
    static func current(at date: Date = .now) -> StudyTerm {
        (2...6).contains(Calendar.plan.component(.month, from: date)) ? .summer : .winter
    }

    /// The usual term of the semester in a plan name such as "Inf/NZ/Ist/2sem/1gr/b", or nil if
    /// the name has no semester (a teacher's or room's plan).
    static func usual(forPlanNamed name: String) -> StudyTerm? {
        guard let match = name.firstMatch(of: #/(?:^|/)(\d+)\s*sem(?:/|$)/#), let number = Int(match.1) else { return nil }
        return number.isMultiple(of: 2) ? .summer : .winter
    }
}

/// Cache of abbreviation → full name lookups, so refreshes only scrape what's new.
struct NameDirectory: Codable {
    var subjects: [String: String] = [:]
    var teacherIDs: [String: Int] = [:]
    var teachers: [String: String] = [:]
    var rooms: Set<String> = []

    mutating func merge(_ page: PlanPage) {
        subjects.merge(page.subjects) { _, new in new }
        teacherIDs.merge(page.teacherIDs) { _, new in new }
        rooms.formUnion(page.roomCodes)
    }
}

extension Calendar {
    /// Gregorian calendar with weeks starting on Monday, as in the university plan. Days are in
    /// Polish time, where the classes are, whatever the device's time zone.
    static let plan: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .warsaw
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

extension Date {
    /// Formatted in Polish time, where the classes are, whatever the device's time zone.
    func planFormatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = .warsaw
        return formatted(style)
    }

    /// The time of day in Polish time: "13:15", or "1:15 PM" with a 12-hour clock.
    var planTime: String { planFormatted(Date.FormatStyle(date: .omitted, time: .shortened)) }
}
