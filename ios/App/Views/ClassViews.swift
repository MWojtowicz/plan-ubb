import SwiftUI

/// A list row: time column, then subject, location and teacher.
struct ClassRow: View {
    let event: ClassEvent
    var now: Date = .now

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.start, style: .time).font(.subheadline.weight(.semibold))
                Text(event.end, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(minWidth: 52, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(event.tint)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.subjectName).font(.headline)
                    Spacer(minLength: 4)
                    KindBadge(event: event)
                }
                Label(event.location, systemImage: "mappin.and.ellipse")
                Label(event.teacherNames, systemImage: "person")
                if event.isRunning(at: now) {
                    Text("Ends in \(Text(timerInterval: event.start...event.end, countsDown: true))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(event.tint)
                }
            }
            .font(.subheadline)
            .labelStyle(CompactLabelStyle())
        }
        .padding(.vertical, 4)
    }
}

struct KindBadge: View {
    let event: ClassEvent

    var body: some View {
        Text(event.kindName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(event.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(event.tint)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(.secondary).frame(width: 16)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}

/// Large card for the class that is running right now.
struct NowCard: View {
    let event: ClassEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Now", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(event.tint)
                Spacer()
                KindBadge(event: event)
            }
            Text(event.subjectName).font(.title3.bold())
            Text(timerInterval: event.start...event.end, countsDown: true)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            ProgressView(timerInterval: event.start...event.end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                Text("until \(event.end.formatted(date: .omitted, time: .shortened))")
            }
            .tint(event.tint)
            VStack(alignment: .leading, spacing: 4) {
                Label(event.location, systemImage: "mappin.and.ellipse")
                Label(event.teacherNames, systemImage: "person")
            }
            .font(.subheadline)
            .labelStyle(CompactLabelStyle())
        }
        .padding(.vertical, 6)
    }
}

struct ClassDetailView: View {
    let event: ClassEvent

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.subjectName).font(.title2.bold())
                    HStack {
                        KindBadge(event: event)
                        Text(event.subjectCode).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("When") {
                LabeledContent("Date", value: event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                LabeledContent("Time", value: event.timeRange)
                LabeledContent("Duration", value: Duration.seconds(event.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            }
            Section(event.rooms.count > 1 ? String(localized: "Rooms") : String(localized: "Room")) {
                ForEach(event.rooms, id: \.self) { Text($0) }
            }
            Section(event.teachers.count > 1 ? String(localized: "Teachers") : String(localized: "Teacher")) {
                ForEach(event.teachers, id: \.self) { Text($0) }
            }
        }
        .navigationTitle(event.subjectCode)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }
}

extension Date {
    var daySectionTitle: String {
        let cal = Calendar.plan
        let base = formatted(.dateTime.weekday(.wide).day().month(.wide))
        if cal.isDateInToday(self) { return String(localized: "Today · \(base)") }
        if cal.isDateInTomorrow(self) { return String(localized: "Tomorrow · \(base)") }
        return base
    }
}

/// Groups events by calendar day, preserving order.
func groupedByDay(_ events: [ClassEvent]) -> [(day: Date, events: [ClassEvent])] {
    let cal = Calendar.plan
    var result: [(day: Date, events: [ClassEvent])] = []
    for event in events {
        let day = cal.startOfDay(for: event.start)
        if result.last?.day == day {
            result[result.count - 1].events.append(event)
        } else {
            result.append((day, [event]))
        }
    }
    return result
}
