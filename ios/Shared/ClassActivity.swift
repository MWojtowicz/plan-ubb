import ActivityKit
import Foundation

/// Live Activity for a day of classes (lock screen banner + Dynamic Island).
///
/// The state holds the whole day, not just the running class. The views work out
/// "in class / break / done" when they render, and the countdowns and progress bars
/// tick on their own. So between updates the banner only goes stale at class boundaries.
/// The app sets `staleDate` to the next boundary so the system redraws it there.
struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Today's classes, sorted by start.
        var classes: [ActivityClass]
    }

    var planName: String?
}

/// Trimmed-down `ClassEvent`. ActivityKit caps the payload at 4 KB.
struct ActivityClass: Codable, Hashable, Identifiable {
    var start: Date
    var end: Date
    var code: String
    var name: String
    var kind: String
    var room: String
    var teacher: String

    var id: Date { start }
    var kindName: String { ClassEvent.kindName(for: kind) }

    init(_ event: ClassEvent) {
        start = event.start
        end = event.end
        code = event.subjectCode
        name = event.subjectName
        kind = event.kindCode
        room = event.location
        teacher = event.teacherNames
    }
}

extension ClassActivityAttributes.ContentState {
    enum Phase {
        case inClass(ActivityClass, next: ActivityClass?)
        /// `since` is the end of the previous class, or nil before the first one.
        case waiting(for: ActivityClass, since: Date?)
        case done
    }

    /// The day's classes for `date`. Returns nil once they're all over.
    init?(snapshot: ScheduleSnapshot, at date: Date, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var classes = snapshot.events(from: dayStart, to: dayEnd).map(ActivityClass.init)
        guard classes.contains(where: { $0.end > date }) else { return nil }
        // Keep well under the 4 KB limit: drop finished classes first, then the latest ones.
        while classes.count > 1, (try? JSONEncoder().encode(classes))?.count ?? 0 > 3000 {
            if let first = classes.first, first.end <= date { classes.removeFirst() } else { classes.removeLast() }
        }
        self.classes = classes
    }

    func phase(at date: Date) -> Phase {
        if let i = classes.firstIndex(where: { $0.start <= date && date < $0.end }) {
            return .inClass(classes[i], next: classes.dropFirst(i + 1).first)
        }
        if let next = classes.first(where: { $0.start > date }) {
            return .waiting(for: next, since: classes.last(where: { $0.end <= date })?.end)
        }
        return .done
    }

    /// The next moment the banner needs to change: a class starting or ending.
    func nextBoundary(after date: Date) -> Date? {
        classes.flatMap { [$0.start, $0.end] }.filter { $0 > date }.min()
    }

    var dayRange: ClosedRange<Date>? {
        guard let first = classes.first, let last = classes.map(\.end).max() else { return nil }
        return first.start...last
    }
}
