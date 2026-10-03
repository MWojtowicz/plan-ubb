import SwiftUI

struct UpcomingView: View {
    @Environment(ScheduleViewModel.self) private var model

    var body: some View {
        NavigationStack {
            // Re-evaluates every 15 s so "now"/"next" move on; the countdowns themselves
            // are rendered live by the system.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                list(now: context.date)
            }
            .navigationTitle("Upcoming")
            .navigationDestination(for: ClassEvent.self) { ClassDetailView(event: $0) }
        }
    }

    private func list(now: Date) -> some View {
        List {
            if let error = model.errorMessage {
                Section { ErrorBanner(message: error) }
            }

            if let snapshot = model.snapshot {
                if let current = snapshot.current(at: now) {
                    Section {
                        NavigationLink(value: current) { NowCard(event: current) }
                    }
                }

                let upcoming = snapshot.upcoming(after: now, limit: 30)
                if let next = upcoming.first {
                    Section {
                        NextSummary(event: next, now: now)
                    }
                }
                ForEach(groupedByDay(upcoming), id: \.day) { group in
                    Section(group.day.daySectionTitle) {
                        ForEach(group.events) { event in
                            NavigationLink(value: event) { ClassRow(event: event, now: now) }
                        }
                    }
                }
                if upcoming.isEmpty && snapshot.current(at: now) == nil {
                    ContentUnavailableView("No upcoming classes", systemImage: "checkmark.circle",
                                           description: Text("There are no more classes in this plan."))
                }
            } else if model.isLoading {
                loading
            } else {
                ContentUnavailableView("No schedule yet", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Pull to refresh."))
            }
        }
        .refreshable { await model.refresh() }
    }

    private var loading: some View {
        HStack {
            Spacer()
            ProgressView("Downloading plan…")
            Spacer()
        }
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}

/// One-line summary: when the next class starts.
private struct NextSummary: View {
    let event: ClassEvent
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.forward.circle.fill")
                .font(.title2)
                .foregroundStyle(event.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next: \(event.subjectName)").font(.subheadline.weight(.semibold))
                Text(startDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var startDescription: String {
        let relative = event.start.formatted(.relative(presentation: .named))
        return "\(relative) · \(event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(event.location)"
    }
}
