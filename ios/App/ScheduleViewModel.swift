import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class ScheduleViewModel {
    private(set) var snapshot: ScheduleSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var source: PlanSource
    /// False on first launch, until a group is picked.
    private(set) var hasChosenSource: Bool
    /// The Live Activity setting, shared by the button on Upcoming and the switch in Settings.
    var liveActivityEnabled: Bool {
        didSet { LiveActivityController.isEnabled = liveActivityEnabled }
    }

    private let store: ScheduleStore

    init(store: ScheduleStore = .shared) {
        self.store = store
        source = store.source
        hasChosenSource = store.hasChosenSource
        liveActivityEnabled = store.liveActivityEnabled
        snapshot = store.loadSnapshot()
    }

    var events: [ClassEvent] { snapshot?.events ?? [] }

    /// Refreshes when there's no data yet or it's older than `maxAge`.
    func refreshIfNeeded(maxAge: TimeInterval = 60 * 60) async {
        guard hasChosenSource else { return }
        guard let snapshot, snapshot.source == source,
              Date().timeIntervalSince(snapshot.fetchedAt) < maxAge
        else {
            await refresh()
            return
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await store.refresh()
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
            await LiveActivityController.sync()
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func changeSource(to newSource: PlanSource) async {
        let isFirstChoice = !hasChosenSource
        store.source = newSource
        hasChosenSource = true
        guard newSource != source || isFirstChoice else { return }
        store.clear()
        source = newSource
        snapshot = nil
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
        await LiveActivityController.endAll()
        await refresh()
    }
}
