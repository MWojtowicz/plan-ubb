import Foundation

/// Persists the schedule in the App Group container so the widget can read what the app downloaded.
final class ScheduleStore {
    static let appGroupID = "group.it.mwojtowicz.PlanUbb"
    static let shared = ScheduleStore()

    private let defaults: UserDefaults
    private let folder: URL

    init() {
        defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = container.appendingPathComponent("Schedule", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// False until the user picks a group (first launch). `source` falls back to the default until then.
    var hasChosenSource: Bool { defaults.data(forKey: "source") != nil }

    var source: PlanSource {
        get {
            defaults.data(forKey: "source").flatMap { try? JSONDecoder().decode(PlanSource.self, from: $0) } ?? .default
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "source")
        }
    }

    /// Show the "classes today" Live Activity. On by default.
    var liveActivityEnabled: Bool {
        get { defaults.object(forKey: "liveActivityEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "liveActivityEnabled") }
    }

    /// Back to first-launch state: no plan chosen, nothing cached.
    func forgetSource() {
        defaults.removeObject(forKey: "source")
        clear()
    }

    func loadSnapshot() -> ScheduleSnapshot? { load("snapshot.json") }
    func saveSnapshot(_ snapshot: ScheduleSnapshot) { write(snapshot, to: "snapshot.json") }

    func loadDirectory() -> NameDirectory { load("names.json") ?? NameDirectory() }
    func saveDirectory(_ directory: NameDirectory) { write(directory, to: "names.json") }

    func clear() {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("snapshot.json"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("names.json"))
    }

    /// Downloads the current source's plan and stores it. Throws on network/parse failure.
    @discardableResult
    func refresh(service: ScheduleService = ScheduleService()) async throws -> ScheduleSnapshot {
        let (snapshot, directory) = try await service.fetch(source: source, directory: loadDirectory())
        saveDirectory(directory)
        saveSnapshot(snapshot)
        return snapshot
    }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}
