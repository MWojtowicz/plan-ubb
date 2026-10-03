import SwiftUI

struct SettingsView: View {
    @Environment(ScheduleViewModel.self) private var model
    @State private var planInput = ""
    @State private var inputError: String?
    @State private var showsGroupPicker = false
    @State private var liveActivityOn = LiveActivityController.isEnabled
    @State private var liveActivityRunning = LiveActivityController.isRunning

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Plan", value: model.snapshot?.planName ?? "—")
                    Button("Change group…") { showsGroupPicker = true }
                    LabeledContent("Classes", value: "\(model.events.count)")
                    LabeledContent("Updated") {
                        if let date = model.snapshot?.fetchedAt {
                            Text(date, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    }
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        HStack {
                            Text("Refresh now")
                            if model.isLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isLoading)
                    if let error = model.errorMessage {
                        ErrorBanner(message: error)
                    }
                }

                Section {
                    Toggle("Show during classes", isOn: $liveActivityOn)
                        .onChange(of: liveActivityOn) { _, on in
                            LiveActivityController.isEnabled = on
                            if !on { liveActivityRunning = false }
                        }
                    Button(liveActivityRunning ? String(localized: "Update now") : String(localized: "Start now")) {
                        Task {
                            await LiveActivityController.sync(force: true)
                            liveActivityRunning = LiveActivityController.isRunning
                        }
                    }
                    .disabled(!LiveActivityController.isAllowed)
                } header: {
                    Text("Live Activity")
                } footer: {
                    if LiveActivityController.isAllowed {
                        Text("Shows today's classes on the Lock Screen and in the Dynamic Island: a countdown, the room, and a timeline of the day. It starts when you open the app during a class or up to an hour before one, and ends after the last class. iOS limits a Live Activity to 8 hours, so on long days open the app again to restart it.")
                    } else {
                        Text("Live Activities are turned off for Plan UBB in the Settings app.")
                    }
                }

                Section {
                    TextField("Plan URL or ID", text: $planInput, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Use this plan") { apply() }
                        .disabled(planInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let inputError {
                        Text(inputError).font(.footnote).foregroundStyle(.red)
                    }
                    Link(destination: model.source.webURL) {
                        Label("Open plan on plany.ubb.edu.pl", systemImage: "safari")
                    }
                } header: {
                    Text("Plan address")
                } footer: {
                    Text("Or paste the address of any plan from plany.ubb.edu.pl (group, teacher or room). Current: type \(model.source.type), id \(model.source.id).")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showsGroupPicker) {
                GroupPickerView(current: model.source) { source in
                    showsGroupPicker = false
                    planInput = source.webURL.absoluteString
                    Task { await model.changeSource(to: source) }
                }
            }
            .onAppear {
                planInput = model.source.webURL.absoluteString
                liveActivityRunning = LiveActivityController.isRunning
            }
        }
    }

    private func apply() {
        guard let source = PlanSource(string: planInput) else {
            inputError = String(localized: "That doesn't look like a plan URL or numeric ID.")
            return
        }
        inputError = nil
        Task { await model.changeSource(to: source) }
    }
}
