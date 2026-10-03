import SwiftUI

struct WeekView: View {
    @Environment(ScheduleViewModel.self) private var model
    @State private var weekStart = Calendar.plan.startOfWeek(for: .now)

    private var cal: Calendar { .plan }

    /// Every week from the first to the last class (always including the current week),
    /// so swiping between pages walks through the semester week by week.
    private var weeks: [Date] {
        let thisWeek = cal.startOfWeek(for: .now)
        let first = min(model.events.first.map { cal.startOfWeek(for: $0.start) } ?? thisWeek, thisWeek)
        let last = max(model.events.last.map { cal.startOfWeek(for: $0.start) } ?? thisWeek, thisWeek)
        var result: [Date] = []
        var week = first
        while week <= last {
            result.append(week)
            week = cal.date(byAdding: .weekOfYear, value: 1, to: week)!
        }
        return result
    }

    /// Mondays of all weeks that have at least one class.
    private var weeksWithClasses: [Date] {
        Array(Set(model.events.map { cal.startOfWeek(for: $0.start) })).sorted()
    }

    var body: some View {
        let weeks = weeks
        NavigationStack {
            VStack(spacing: 0) {
                weekHeader(weeks)
                Divider()
                if let error = model.errorMessage {
                    ErrorBanner(message: error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
                // A paging TabView gives native swiping between weeks without
                // fighting the vertical scrolling of each page.
                TabView(selection: $weekStart) {
                    ForEach(weeks, id: \.self) { monday in
                        WeekPage(monday: monday, nextWeekWithClasses: weeksWithClasses.first { $0 > monday }) {
                            weekStart = $0
                        }
                        .tag(monday)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Week")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ClassEvent.self) { ClassDetailView(event: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { withAnimation { weekStart = cal.startOfWeek(for: .now) } }
                        .disabled(weekStart == cal.startOfWeek(for: .now))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(weeksWithClasses, id: \.self) { monday in
                            Button {
                                withAnimation { weekStart = monday }
                            } label: {
                                if monday == weekStart {
                                    Label(weekTitle(monday), systemImage: "checkmark")
                                } else {
                                    Text(weekTitle(monday))
                                }
                            }
                        }
                    } label: {
                        Label("Weeks", systemImage: "list.bullet")
                    }
                    .disabled(weeksWithClasses.isEmpty)
                }
            }
        }
    }

    private func weekHeader(_ weeks: [Date]) -> some View {
        let index = weeks.firstIndex(of: weekStart)
        return HStack {
            Button { step(-1, in: weeks) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 36)
            }
            .disabled(index == nil || index == 0)
            Spacer()
            VStack(spacing: 2) {
                Text(weekTitle(weekStart)).font(.headline).monospacedDigit()
                Text(weekSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { step(1, in: weeks) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 36)
            }
            .disabled(index == nil || index == weeks.count - 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var weekSubtitle: String {
        let end = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let events = model.snapshot?.events(from: weekStart, to: end) ?? []
        if events.isEmpty { return String(localized: "No classes") }
        let hours = (events.reduce(0) { $0 + $1.duration } / 3600).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(events.count) classes · \(hours) h")
    }

    private func weekTitle(_ monday: Date) -> String {
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
        return "\(monday.formatted(.dateTime.day().month(.abbreviated))) – \(sunday.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func step(_ delta: Int, in weeks: [Date]) {
        guard let i = weeks.firstIndex(of: weekStart), weeks.indices.contains(i + delta) else { return }
        withAnimation { weekStart = weeks[i + delta] }
    }
}

/// One week: a list in portrait, side-by-side day columns when the height is compact (landscape).
private struct WeekPage: View {
    @Environment(ScheduleViewModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let monday: Date
    let nextWeekWithClasses: Date?
    let jump: (Date) -> Void

    private var days: [(day: Date, events: [ClassEvent])] {
        let end = Calendar.plan.date(byAdding: .day, value: 7, to: monday)!
        return groupedByDay(model.snapshot?.events(from: monday, to: end) ?? [])
    }

    var body: some View {
        let days = days
        Group {
            if days.isEmpty {
                empty
            } else if verticalSizeClass == .compact {
                DayColumns(days: days)
            } else {
                List {
                    ForEach(days, id: \.day) { group in
                        Section(group.day.daySectionTitle) {
                            ForEach(group.events) { event in
                                NavigationLink(value: event) { ClassRow(event: event) }
                            }
                        }
                    }
                }
                .refreshable { await model.refresh() }
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        if model.isLoading && model.snapshot == nil {
            ProgressView("Downloading plan…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("No classes this week", systemImage: "calendar")
            } actions: {
                if let next = nextWeekWithClasses {
                    Button("Go to next week with classes") { withAnimation { jump(next) } }
                }
            }
        }
    }
}

/// Days laid out next to each other, like the timetable on the website.
private struct DayColumns: View {
    let days: [(day: Date, events: [ClassEvent])]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let available = proxy.size.width - spacing * CGFloat(days.count + 1)
            let width = max(260, available / CGFloat(days.count))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.day.daySectionTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                            ScrollView(.vertical) {
                                VStack(spacing: 8) {
                                    ForEach(group.events) { event in
                                        NavigationLink(value: event) {
                                            ClassRow(event: event)
                                                .padding(.horizontal, 10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(.secondarySystemGroupedBackground),
                                                            in: RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                // Room to scroll the last class clear of the floating tab bar.
                                .padding(.bottom, 80)
                            }
                            .scrollIndicators(.hidden)
                        }
                        .frame(width: width)
                    }
                }
                .padding(.horizontal, spacing)
            }
            .scrollDisabled(width * CGFloat(days.count) + spacing * CGFloat(days.count + 1) <= proxy.size.width)
        }
        .background(Color(.systemGroupedBackground))
    }
}
