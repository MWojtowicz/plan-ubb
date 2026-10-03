import SwiftUI

@main
struct PlanUbbApp: App {
    @State private var model: ScheduleViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        Self.applyUITestArguments()
        #endif
        _model = State(initialValue: ScheduleViewModel())
    }

    #if DEBUG
    /// `-UITestPlan <id>` sets the plan when none is chosen yet, skipping the first-launch picker.
    /// `-UITestResetPlan` forgets the chosen plan, bringing the picker back.
    private static func applyUITestArguments() {
        let args = ProcessInfo.processInfo.arguments
        let store = ScheduleStore.shared
        if args.contains("-UITestResetPlan") {
            store.forgetSource()
        } else if let i = args.firstIndex(of: "-UITestPlan"), i + 1 < args.count,
                  let id = Int(args[i + 1]), !store.hasChosenSource {
            store.source = PlanSource(type: 0, id: id)
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await LiveActivityController.sync()
                    await model.refreshIfNeeded()
                }
        }
        .backgroundTask(.appRefresh(LiveActivityController.refreshTaskID)) {
            await LiveActivityController.sync()
        }
    }
}

struct RootView: View {
    @Environment(ScheduleViewModel.self) private var model

    var body: some View {
        tabs.fullScreenCover(isPresented: .constant(!model.hasChosenSource)) {
            GroupPickerView(isOnboarding: true) { source in
                Task { await model.changeSource(to: source) }
            }
        }
    }

    private var tabs: some View {
        TabView {
            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "clock") }
            WeekView()
                .tabItem { Label("Week", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
