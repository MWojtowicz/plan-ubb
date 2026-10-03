import ActivityKit
import BackgroundTasks
import Foundation
import os

/// Starts, updates and ends the "classes today" Live Activity.
///
/// iOS only lets the app *start* a Live Activity while it's in the foreground (there's no
/// push server here). Updates also work in the background, so a background refresh is
/// scheduled for the next class boundary. If iOS runs it late, the banner still shows the
/// right state, because the views work out the phase themselves and redraw at `staleDate`.
@MainActor
enum LiveActivityController {
    static let refreshTaskID = "it.mwojtowicz.PlanUbb.liveActivity"
    private static let log = Logger(subsystem: "it.mwojtowicz.PlanUbb", category: "LiveActivity")
    /// Auto-start only when a class is running or the next one starts within this window.
    /// Live Activities last at most 8 hours, so starting early in the morning would end it mid-day.
    static let autoStartLead: TimeInterval = 60 * 60

    static var isEnabled: Bool {
        get { ScheduleStore.shared.liveActivityEnabled }
        set {
            ScheduleStore.shared.liveActivityEnabled = newValue
            Task { newValue ? await sync() : await endAll() }
        }
    }

    static var isRunning: Bool { !Activity<ClassActivityAttributes>.activities.isEmpty }
    static var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Brings the activity in line with the stored schedule.
    /// `force` starts it even outside the auto-start window (the "Start now" button).
    static func sync(force: Bool = false, now: Date = .now) async {
        let store = ScheduleStore.shared
        guard store.liveActivityEnabled || force,
              let snapshot = store.loadSnapshot(),
              let state = ClassActivityAttributes.ContentState(snapshot: snapshot, at: now)
        else {
            await endAll()
            return
        }

        let content = ActivityContent(state: state, staleDate: state.nextBoundary(after: now))
        let activities = Activity<ClassActivityAttributes>.activities
        log.info("sync: \(activities.count) running, allowed: \(isAllowed), \(state.classes.count) classes today")
        if let activity = activities.first {
            await activity.update(content)
            for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if force || startsSoon(state, now: now), isAllowed {
            do {
                _ = try Activity.request(
                    attributes: ClassActivityAttributes(planName: snapshot.planName),
                    content: content
                )
            } catch {
                log.error("Couldn't start Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
        scheduleRefresh(at: state.nextBoundary(after: now))
    }

    static func endAll() async {
        for activity in Activity<ClassActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func startsSoon(_ state: ClassActivityAttributes.ContentState, now: Date) -> Bool {
        guard let upcoming = state.classes.first(where: { $0.end > now }) else { return false }
        return upcoming.start.timeIntervalSince(now) <= autoStartLead
    }

    private static func scheduleRefresh(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        guard let date, isRunning else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Couldn't schedule Live Activity refresh: \(error.localizedDescription, privacy: .public)")
        }
    }
}
