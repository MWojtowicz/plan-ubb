import SwiftUI
import WidgetKit

@main
struct PlanUbbWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurrentClassWidget()
        ClassLiveActivity()
    }
}

struct CurrentClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentClass", provider: ClassProvider()) { entry in
            CurrentClassWidgetView(entry: entry)
        }
        .configurationDisplayName("Current class")
        .description("The class running now with a countdown to its end, or the next one.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct ClassEntry: TimelineEntry {
    let date: Date
    let current: ClassEvent?
    let next: ClassEvent?
    let hasData: Bool
}

struct ClassProvider: TimelineProvider {
    private static let staleAfter: TimeInterval = 6 * 60 * 60

    func placeholder(in context: Context) -> ClassEntry {
        ClassEntry(date: .now, current: .sample, next: nil, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClassEntry) -> Void) {
        if context.isPreview, ScheduleStore.shared.loadSnapshot() == nil {
            completion(placeholder(in: context))
            return
        }
        let snapshot = ScheduleStore.shared.loadSnapshot()
        completion(Self.entry(at: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassEntry>) -> Void) {
        Task {
            let store = ScheduleStore.shared
            var snapshot = store.loadSnapshot()
            // Before the first group is picked there's nothing to download yet.
            if store.hasChosenSource, snapshot == nil || Date().timeIntervalSince(snapshot!.fetchedAt) > Self.staleAfter {
                if let fresh = try? await store.refresh() { snapshot = fresh }
            }
            completion(Self.timeline(snapshot: snapshot, now: .now))
        }
    }

    /// One entry at every class start/end over the next 3 days, so the widget flips
    /// between "now" and "next" exactly on time. The countdown itself is rendered by
    /// the system (`Text(timerInterval:)`), so no per-minute entries are needed.
    static func timeline(snapshot: ScheduleSnapshot?, now: Date) -> Timeline<ClassEntry> {
        let reload = now.addingTimeInterval(4 * 60 * 60)
        guard let snapshot else {
            return Timeline(entries: [entry(at: now, snapshot: nil)], policy: .after(now.addingTimeInterval(30 * 60)))
        }
        let horizon = now.addingTimeInterval(3 * 24 * 60 * 60)
        var dates: Set<Date> = [now]
        for event in snapshot.events where event.end > now && event.start < horizon {
            if event.start > now { dates.insert(event.start) }
            dates.insert(event.end)
        }
        let entries = dates.sorted().prefix(100).map { entry(at: $0, snapshot: snapshot) }
        return Timeline(entries: Array(entries), policy: .after(reload))
    }

    static func entry(at date: Date, snapshot: ScheduleSnapshot?) -> ClassEntry {
        ClassEntry(
            date: date,
            current: snapshot?.current(at: date),
            next: snapshot?.upcoming(after: date, limit: 1).first,
            hasData: snapshot != nil
        )
    }
}

// MARK: - Views

struct CurrentClassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClassEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            CircularView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            RectangularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SystemView(entry: entry, isMedium: family == .systemMedium)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }
}

private struct RectangularView: View {
    let entry: ClassEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let e = entry.current {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(timerInterval: e.start...e.end, countsDown: true)
                        .monospacedDigit()
                    Text("· \(e.location)").lineLimit(1)
                }
                .font(.headline)
                .widgetAccentable()
                Text(e.subjectName).font(.body.weight(.semibold)).lineLimit(1)
                Text(e.teacherNames).lineLimit(1).foregroundStyle(.secondary)
            } else if let e = entry.next {
                Text("Next · \(e.start.formatted(nextFormat(e)))")
                    .font(.headline)
                    .widgetAccentable()
                    .lineLimit(1)
                Text(e.subjectName).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(e.location) · \(e.teacherNames)").lineLimit(1).foregroundStyle(.secondary)
            } else {
                Text(entry.hasData ? String(localized: "No upcoming classes") : String(localized: "Open Plan UBB to load"))
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let entry: ClassEntry

    var body: some View {
        if let e = entry.current {
            Text("\(Image(systemName: "timer")) \(Text(timerInterval: e.start...e.end, countsDown: true)) \(e.subjectCode) \(e.location)")
        } else if let e = entry.next {
            Text("\(e.start.formatted(nextFormat(e))) \(e.subjectCode) \(e.location)")
        } else {
            Text("No classes")
        }
    }
}

private struct CircularView: View {
    let entry: ClassEntry

    var body: some View {
        if let e = entry.current {
            ProgressView(timerInterval: e.start...e.end, countsDown: true) {
                Text(e.subjectCode)
            } currentValueLabel: {
                Text(e.subjectCode).font(.caption2.weight(.semibold)).minimumScaleFactor(0.6)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else if let e = entry.next {
            VStack(spacing: 0) {
                Text(e.subjectCode).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(e.start, style: .time).font(.caption2).monospacedDigit().minimumScaleFactor(0.6)
            }
        } else {
            Image(systemName: "calendar")
        }
    }
}

private struct SystemView: View {
    let entry: ClassEntry
    let isMedium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = entry.current {
                Label("Now", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(e.tint)
                Text(e.subjectName).font(.headline).lineLimit(2)
                Text(timerInterval: e.start...e.end, countsDown: true)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                details(e)
            } else if let e = entry.next {
                Label("Next · \(e.start.formatted(nextFormat(e)))", systemImage: "arrow.forward.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(e.tint)
                Text(e.subjectName).font(.headline).lineLimit(2)
                details(e)
            } else {
                Label(entry.hasData ? String(localized: "No upcoming classes") : String(localized: "Open Plan UBB to load the plan"), systemImage: "calendar")
                    .font(.headline)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func details(_ e: ClassEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(e.location, systemImage: "mappin.and.ellipse")
            Label(e.teacherNames, systemImage: "person")
            if isMedium { Label("\(e.kindName) · \(e.timeRange)", systemImage: "clock") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// "14:30" today, "Sat 08:00" on other days.
private func nextFormat(_ e: ClassEvent) -> Date.FormatStyle {
    Calendar.current.isDateInToday(e.start)
        ? .dateTime.hour().minute()
        : .dateTime.weekday(.abbreviated).hour().minute()
}

extension ClassEvent {
    static let sample = ClassEvent(
        id: "sample",
        start: Date().addingTimeInterval(-30 * 60),
        end: Date().addingTimeInterval(60 * 60),
        subjectCode: "BdI",
        subjectName: "Bazy danych I",
        kindCode: "wyk",
        teacherCodes: ["ANo"],
        teachers: ["dr hab. inż. Andrzej Nowak"],
        rooms: ["L132"]
    )
}

#Preview(as: .accessoryRectangular) {
    CurrentClassWidget()
} timeline: {
    ClassEntry(date: .now, current: .sample, next: nil, hasData: true)
    ClassEntry(date: .now, current: nil, next: .sample, hasData: true)
}
