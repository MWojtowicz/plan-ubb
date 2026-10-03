import ActivityKit
import SwiftUI
import WidgetKit

struct ClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            LockScreenBanner(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // Live Activity views are redrawn at each update and at the stale date, which
            // the app sets to the next class boundary. So `.now` is the right moment here.
            let phase = context.state.phase(at: .now)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let e = phase.focus {
                        Label(e.code, systemImage: phase.symbol)
                            .font(.headline)
                            .foregroundStyle(e.tint)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let e = phase.focus {
                        Label(e.room, systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let e = phase.focus {
                        Text(e.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(phase.caption)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            CountdownText(phase: phase)
                                .font(.system(.title, design: .rounded).weight(.bold))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 140, alignment: .trailing)
                        }
                        PhaseProgress(phase: phase)
                        if let next = phase.upNext {
                            NextLine(next: next).font(.caption)
                        }
                    }
                }
            } compactLeading: {
                if let e = phase.focus {
                    Text(e.code)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(e.tint)
                        .lineLimit(1)
                }
            } compactTrailing: {
                CountdownText(phase: phase)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56)
            } minimal: {
                if case .inClass(let e, _) = phase {
                    ProgressView(timerInterval: e.start...e.end, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .tint(e.tint)
                } else {
                    Image(systemName: phase.symbol)
                }
            }
            .keylineTint(phase.focus?.tint)
        }
    }
}

// MARK: - Lock screen

private struct LockScreenBanner: View {
    let state: ClassActivityAttributes.ContentState

    // iOS caps the lock screen banner at about 160 pt tall and cuts off anything beyond,
    // so this is kept dense: header, countdown + room, subject, day timeline.
    var body: some View {
        let phase = state.phase(at: .now)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(phase.caption, systemImage: phase.symbol)
                    .foregroundStyle(phase.focus?.tint ?? .white)
                Spacer()
                if let next = phase.upNext {
                    Text("Next \(next.start, style: .time) · \(next.room)")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .font(.caption.weight(.bold))
            .lineLimit(1)

            if let e = phase.focus {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    CountdownText(phase: phase)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Label(e.room, systemImage: "mappin.and.ellipse")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.name).font(.headline).lineLimit(1)
                    Text("\(e.kindName) · \(e.timeRange) · \(e.teacher)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            } else {
                Text("No more classes today")
                    .font(.title3.weight(.bold))
            }

            if let range = state.dayRange {
                DayTimeline(classes: state.classes, range: range)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The day at a glance: one block per class, and a bar under it that fills as the day goes by.
private struct DayTimeline: View {
    let classes: [ActivityClass]
    let range: ClosedRange<Date>

    var body: some View {
        let now = Date.now
        VStack(spacing: 3) {
            GeometryReader { geo in
                let total = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
                ForEach(classes) { c in
                    let x = c.start.timeIntervalSince(range.lowerBound) / total * geo.size.width
                    let w = c.end.timeIntervalSince(c.start) / total * geo.size.width
                    RoundedRectangle(cornerRadius: 3)
                        .fill(c.tint.opacity(c.end <= now ? 0.4 : 1))
                        .frame(width: max(w - 2, 3), height: geo.size.height)
                        .offset(x: x)
                }
            }
            .frame(height: 8)
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(.white)
        }
    }
}

// MARK: - Building blocks

/// Counts down to the end of the running class, or to the start of the next one.
private struct CountdownText: View {
    let phase: ClassActivityAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .inClass(let e, _):
            Text(timerInterval: e.start...e.end, countsDown: true).monospacedDigit()
        case .waiting(let e, let since):
            Text(timerInterval: min(since ?? .now, e.start)...e.start, countsDown: true).monospacedDigit()
        case .done:
            Image(systemName: "checkmark")
        }
    }
}

/// The running class's progress, or how far through the break you are.
private struct PhaseProgress: View {
    let phase: ClassActivityAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .inClass(let e, _):
            bar(e.start...e.end, tint: e.tint)
        case .waiting(let e, let since?) where since < e.start:
            bar(since...e.start, tint: e.tint.opacity(0.6))
        default:
            EmptyView()
        }
    }

    private func bar(_ range: ClosedRange<Date>, tint: Color) -> some View {
        ProgressView(timerInterval: range, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(tint)
    }
}

private struct NextLine: View {
    let next: ActivityClass

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.forward.circle.fill").foregroundStyle(next.tint)
            Text("Next \(next.start, style: .time)").fontWeight(.semibold).monospacedDigit()
            Text("\(next.name) · \(next.room)").lineLimit(1)
        }
    }
}

private extension ClassActivityAttributes.ContentState.Phase {
    /// The class the banner is about: the running one, or the next one during a break.
    var focus: ActivityClass? {
        switch self {
        case .inClass(let e, _), .waiting(let e, _): return e
        case .done: return nil
        }
    }

    /// The class after `focus`, shown in the "Next" line.
    var upNext: ActivityClass? {
        if case .inClass(_, let next) = self { return next }
        return nil
    }

    var caption: String {
        switch self {
        case .inClass(let e, _): return String(localized: "NOW · \(e.kindName.uppercased())")
        case .waiting(_, let since): return since == nil ? String(localized: "FIRST CLASS IN") : String(localized: "BREAK · NEXT CLASS IN")
        case .done: return String(localized: "DONE FOR TODAY")
        }
    }

    var symbol: String {
        switch self {
        case .inClass: return "dot.radiowaves.left.and.right"
        case .waiting: return "cup.and.saucer.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

private extension ActivityClass {
    var timeRange: String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

#Preview("Lock screen", as: .content, using: ClassActivityAttributes(planName: "Inf/NZ/Ist/3sem/1gr/b")) {
    ClassLiveActivity()
} contentStates: {
    ClassActivityAttributes.ContentState.sample
}

extension ClassActivityAttributes.ContentState {
    static var sample: Self {
        let now = Date.now
        func make(_ startMin: Double, _ minutes: Double, _ code: String, _ name: String, _ kind: String, _ room: String) -> ActivityClass {
            var c = ActivityClass(.sample)
            c.start = now.addingTimeInterval(startMin * 60)
            c.end = c.start.addingTimeInterval(minutes * 60)
            c.code = code
            c.name = name
            c.kind = kind
            c.room = room
            return c
        }
        return Self(classes: [
            make(-130, 90, "Ak", "Architektura komputerów", "wyk", "L136"),
            make(-30, 90, "BdI", "Bazy danych I", "lab", "L132"),
            make(75, 90, "SoII", "Systemy operacyjne II", "ćw", "L201"),
        ])
    }
}
