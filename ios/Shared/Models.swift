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
    /// Gregorian calendar with weeks starting on Monday, as in the university plan.
    static let plan: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
