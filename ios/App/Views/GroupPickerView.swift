import SwiftUI

/// Drill-down through the site's "Grupy" tree: department → study mode → course → degree →
/// semester → group → subgroup. Each level is downloaded when it's opened, like the site's left frame.
struct GroupPickerView: View {
    /// Shown on first launch: no Cancel, plus a short intro.
    var isOnboarding = false
    var current: PlanSource?
    let onPick: (PlanSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loader = PlanTreeLoader()

    var body: some View {
        NavigationStack {
            GroupLevelView(parent: nil, siblings: [], current: current, isOnboarding: isOnboarding, onPick: onPick)
                .navigationDestination(for: LevelRoute.self) { route in
                    GroupLevelView(parent: route.node, siblings: route.siblings, current: current, isOnboarding: false, onPick: onPick)
                }
                .toolbar {
                    if !isOnboarding {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                }
        }
        .environment(loader)
        .interactiveDismissDisabled(isOnboarding)
    }
}

struct LevelRoute: Hashable {
    let node: PlanTreeNode
    /// The node's siblings, so its title can be shortened the same way as in the list.
    let siblings: [PlanTreeNode]
}

/// Downloads and caches levels of the tree for as long as the picker is open.
@MainActor
@Observable
final class PlanTreeLoader {
    private var cache: [String: [PlanTreeNode]] = [:]
    private let service = PlanTreeService()

    func children(of parent: PlanTreeNode?) async throws -> [PlanTreeNode] {
        let key = parent?.id ?? "root"
        if let cached = cache[key] { return cached }
        let nodes = try await service.children(of: parent)
        cache[key] = nodes
        return nodes
    }
}

private struct GroupLevelView: View {
    let parent: PlanTreeNode?
    let siblings: [PlanTreeNode]
    let current: PlanSource?
    let isOnboarding: Bool
    let onPick: (PlanSource) -> Void

    @Environment(PlanTreeLoader.self) private var loader
    @State private var nodes: [PlanTreeNode]?
    @State private var error: String?
    @State private var query = ""

    var body: some View {
        List {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("Choose your group").font(.title2.bold())
                        Text("Go through your department, study mode, course and semester down to your group and lab subgroup. You can change it later in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let nodes {
                Section {
                    ForEach(filtered(nodes)) { node in row(node, among: nodes) }
                } footer: {
                    if nodes.isEmpty { Text("Nothing here.") }
                }
                if let plan = parent?.plan, !nodes.isEmpty {
                    Section {
                        pickButton(plan) {
                            Label("Use the whole \(parent?.name ?? "") plan", systemImage: "rectangle.stack")
                        }
                    } footer: {
                        Text("Shows the classes of every group below.")
                    }
                }
            } else if let error {
                Section {
                    ErrorBanner(message: error)
                    Button("Try again") { Task { await load() } }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(parent == nil ? .large : .inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic))
        .task { if nodes == nil { await load() } }
    }

    private var title: String {
        guard let parent else { return isOnboarding ? "Plan UBB" : String(localized: "Choose group") }
        return parent.shortName(among: siblings.isEmpty ? [parent] : siblings)
    }

    @ViewBuilder
    private func row(_ node: PlanTreeNode, among nodes: [PlanTreeNode]) -> some View {
        let short = node.shortName(among: nodes)
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(short)
            if short != node.name {
                Text(node.name).font(.caption).foregroundStyle(.secondary)
            }
        }
        if node.isLeaf, let plan = node.plan {
            pickButton(plan) {
                HStack {
                    label
                    Spacer()
                    if plan == current {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        } else {
            NavigationLink(value: LevelRoute(node: node, siblings: nodes)) { label }
        }
    }

    private func pickButton<Label: View>(_ plan: PlanSource, @ViewBuilder label: () -> Label) -> some View {
        Button { onPick(plan) } label: { label() }
            .foregroundStyle(.primary)
    }

    private func filtered(_ nodes: [PlanTreeNode]) -> [PlanTreeNode] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nodes }
        return nodes.filter { $0.name.localizedStandardContains(q) || $0.shortName(among: nodes).localizedStandardContains(q) }
    }

    private func load() async {
        error = nil
        do {
            nodes = try await loader.children(of: parent)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
