import ActivityKit
import BackgroundTasks
import Foundation
import os

/// Starts, updates and ends the "classes today" Live Activity. It's up from the start of the day's
/// first class to the end of the last one.
///
/// Without a push server, the app can only *start* a Live Activity while it's in the foreground.
/// On iOS 26+ it also schedules the next class day's activity ahead of time, and the system starts it
/// by itself when the first class begins. Updates work in the background, so a background refresh is
/// scheduled for the next class boundary. If iOS runs it late, the banner still shows the right state,
/// because the views work out the phase themselves and redraw at `staleDate`.
@MainActor
enum LiveActivityController {
    static let refreshTaskID = "it.mwojtowicz.PlanUbb.liveActivity"
    private static let log = Logger(subsystem: "it.mwojtowicz.PlanUbb", category: "LiveActivity")

    static var isEnabled: Bool {
        get { ScheduleStore.shared.liveActivityEnabled }
        set {
            ScheduleStore.shared.liveActivityEnabled = newValue
            Task { newValue ? await sync() : await endAll() }
        }
    }

    static var isRunning: Bool { Activity<ClassActivityAttributes>.activities.contains { $0.activityState == .active || $0.activityState == .stale } }
    static var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Brings the activities in line with the stored schedule and the clock.
    /// `force` starts today's activity even before the first class (the "Start now" button).
    static func sync(force: Bool = false, now: Date = .now) async {
        let store = ScheduleStore.shared
        guard store.liveActivityEnabled || force, let snapshot = store.loadSnapshot() else {
            await endAll()
            return
        }
        let activities = Activity<ClassActivityAttributes>.activities
        let running = activities.filter { $0.activityState == .active || $0.activityState == .stale }
        // Today's classes, or nil once they're all over.
        let today = ClassActivityAttributes.ContentState(snapshot: snapshot, at: now)
        log.info("sync: \(running.count) running, \(activities.count) total, allowed: \(isAllowed), \(today?.classes.count ?? 0) classes left today")

        if let today {
            let content = ActivityContent(state: today, staleDate: today.nextBoundary(after: now))
            if let activity = running.first {
                await activity.update(content)
                for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else if (force || today.isLive(at: now)), isAllowed {
                // A scheduled one for today hasn't started yet: start it now instead.
                if #available(iOS 26.0, *) {
                    for pending in activities where pending.activityState == .pending { await pending.end(nil, dismissalPolicy: .immediate) }
                }
                do {
                    _ = try Activity.request(attributes: ClassActivityAttributes(planName: snapshot.planName), content: content)
                } catch {
                    log.error("Couldn't start Live Activity: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            // The last class is over.
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        if #available(iOS 26.0, *) {
            await scheduleNextDay(snapshot: snapshot, now: now)
        }
        scheduleRefresh(at: isRunning ? today?.nextBoundary(after: now) : nil)
    }

    static func endAll() async {
        for activity in Activity<ClassActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Schedules the activity for the next class day that hasn't started yet, so the system starts it at
    /// that day's first class without the app being opened. Keeps at most one pending activity.
    @available(iOS 26.0, *)
    private static func scheduleNextDay(snapshot: ScheduleSnapshot, now: Date) async {
        let pending = Activity<ClassActivityAttributes>.activities.filter { $0.activityState == .pending }
        // The first class of the next day whose classes haven't started yet.
        let cal = Calendar.current
        let firstOfEachDay = snapshot.events.enumerated()
            .filter { i, e in i == 0 || !cal.isDate(snapshot.events[i - 1].start, inSameDayAs: e.start) }
            .map(\.element)
        guard isAllowed,
              let first = firstOfEachDay.first(where: { $0.start > now }),
              let state = ClassActivityAttributes.ContentState(snapshot: snapshot, at: first.start)
        else {
            for activity in pending { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        if let existing = pending.first, existing.content.state == state, pending.count == 1 { return }
        for activity in pending { await activity.end(nil, dismissalPolicy: .immediate) }
        do {
            _ = try Activity.request(
                attributes: ClassActivityAttributes(planName: snapshot.planName),
                content: ActivityContent(state: state, staleDate: state.nextBoundary(after: first.start)),
                style: .standard,
                alertConfiguration: AlertConfiguration(
                    title: "\(first.subjectName)",
                    body: "First class · \(first.location)",
                    sound: .default
                ),
                start: first.start
            )
            log.info("Scheduled Live Activity for \(first.start, privacy: .public)")
        } catch {
            log.error("Couldn't schedule Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func scheduleRefresh(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Couldn't schedule Live Activity refresh: \(error.localizedDescription, privacy: .public)")
        }
    }
}
