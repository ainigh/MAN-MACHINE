#if os(macOS)
import SwiftUI
import MpmCore
import MpmHost

/// The app drawn as its parts: who is working, what just passed between two of them, and what went
/// wrong. Still unless something happened (DESIGN §1): a pulse runs only for a fresh hand-off and an
/// arc only while a component is working. Click a part to see its events; click an event for detail.
struct MonitorView: View {
    let monitor: Monitor
    @State private var focus: Component?
    @State private var selected: Int?
    @State private var problemsOnly = false

    var body: some View {
        VStack(spacing: 0) {
            MonitorDiagram(monitor: monitor, focus: $focus)
                .frame(maxWidth: .infinity, minHeight: Theme.MonitorPanel.diagramMinHeight, maxHeight: .infinity)
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
            HStack(spacing: 0) {
                eventList
                Rectangle().fill(Theme.line).frame(width: Theme.hairline)
                MonitorDetail(event: shown.first { $0.id == selected })
                    .frame(minWidth: Theme.MonitorPanel.detailMinWidth, maxWidth: Theme.MonitorPanel.detailWidth)
            }
            .frame(height: Theme.MonitorPanel.inspectorHeight)
        }
        .background(Theme.bg)
        .onChange(of: focus) { _, c in
            selected = nil
            if let c { monitor.acknowledge(c) }
        }
    }

    private var shown: [MonitorEvent] {
        let base = focus.map { monitor.events(touching: $0) } ?? monitor.events
        return (problemsOnly ? base.filter { $0.outcome >= .warning } : base).reversed()
    }

    private var eventList: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s8) {
                Text(focus?.title ?? Strings.monitorAll)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                if focus != nil {
                    Button(Strings.monitorShowAll) { focus = nil }
                        .buttonStyle(LinkButtonStyle())
                }
                Spacer()
                Button(Strings.monitorProblemsOnly) { problemsOnly.toggle() }
                    .buttonStyle(PillButtonStyle(kind: .toggle(problemsOnly), small: true))
                    .accessibilityAddTraits(problemsOnly ? .isSelected : [])
                if monitor.unseenTotal > 0 {
                    Button(Strings.monitorMarkSeen) { monitor.acknowledge() }
                        .buttonStyle(PillButtonStyle(small: true))
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s8)
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
            if shown.isEmpty {
                Text(Strings.monitorEmpty)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown, selection: $selected) { e in
                    MonitorRow(event: e).tag(e.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: Theme.MonitorPanel.listMinWidth, maxWidth: .infinity)
    }
}

// MARK: Diagram

struct MonitorDiagram: View {
    let monitor: Monitor
    @Binding var focus: Component?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True for one pulse length after each new event; the timeline pauses otherwise.
    @State private var pulsing = false
    @State private var pulseEnd: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let width = nodeWidth(geo.size.width)
            TimelineView(.animation(minimumInterval: nil, paused: !pulsing && monitor.activity.isEmpty)) { tl in
                ZStack {
                    Canvas { gc, size in draw(&gc, size: size, now: tl.date) }
                    ForEach(Component.allCases, id: \.self) { c in
                        MonitorNode(component: c, monitor: monitor, selected: focus == c, now: tl.date, width: width)
                            .onTapGesture { focus = focus == c ? nil : c }
                            .position(point(c, in: geo.size))
                    }
                }
            }
        }
        .onChange(of: monitor.events.last?.id) { _, _ in
            pulsing = true
            pulseEnd?.cancel()
            pulseEnd = Task {
                try? await Task.sleep(for: Theme.Motion.pulse + .milliseconds(50))
                guard !Task.isCancelled else { return }
                pulsing = false
            }
        }
    }

    /// Four columns share the width; nodes narrow before they overlap, down to a floor.
    private func nodeWidth(_ width: CGFloat) -> CGFloat {
        let column = (width - 2 * Theme.Space.s16) / 4 - Theme.Space.s8
        return min(Theme.MonitorPanel.node.width, max(Theme.MonitorPanel.nodeMinWidth, column))
    }

    /// The layout's outermost columns and rows sit at the edges of the drawable area.
    private func point(_ c: Component, in size: CGSize) -> CGPoint {
        let p = MonitorLayout.position[c] ?? (0.5, 0.5)
        let xs = MonitorLayout.position.values.map(\.x), ys = MonitorLayout.position.values.map(\.y)
        let (x0, x1) = (xs.min() ?? 0, xs.max() ?? 1), (y0, y1) = (ys.min() ?? 0, ys.max() ?? 1)
        let w = nodeWidth(size.width), h = Theme.MonitorPanel.node.height
        let left = Theme.Space.s16 + w / 2, top = h / 2
        let spanX = max(0, size.width - 2 * left), spanY = max(0, size.height - 2 * top)
        return CGPoint(x: left + (x1 > x0 ? (p.x - x0) / (x1 - x0) : 0.5) * spanX,
                       y: top + (y1 > y0 ? (p.y - y0) / (y1 - y0) : 0.5) * spanY)
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, now: Date) {
        for e in MonitorLayout.edges {
            var path = Path()
            path.move(to: point(e.a, in: size))
            path.addLine(to: point(e.b, in: size))
            let lit = focus.map { e.a == $0 || e.b == $0 } ?? false
            gc.stroke(path, with: .color(lit ? Theme.ink2 : Theme.line), lineWidth: Theme.hairline)
        }
        let duration = Theme.MonitorPanel.pulseSeconds
        for (event, progress) in monitor.inFlight(now: now, duration: duration) {
            guard let to = event.to else { continue }
            let a = point(event.from, in: size), b = point(to, in: size)
            let color = Theme.color(event.outcome)
            // The edge lights in the event's color and fades; with Reduce Motion that is all that happens.
            var edge = Path()
            edge.move(to: a)
            edge.addLine(to: b)
            gc.stroke(edge, with: .color(color.opacity(0.6 * (1 - progress))), lineWidth: Theme.statusStroke)
            guard !reduceMotion else { continue }
            let t = 1 - pow(1 - progress, 2)                                   // easeOut
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let r = Theme.MonitorPanel.pulseDot / 2
            gc.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
        }
    }
}

struct MonitorNode: View {
    let component: Component
    let monitor: Monitor
    let selected: Bool
    let now: Date
    let width: CGFloat

    var body: some View {
        let activity = monitor.activity[component]
        let unseen = monitor.unseen[component]
        let count = monitor.unseenCount[component] ?? 0
        let last = monitor.events(touching: component).last
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.surface)
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(stroke(activity: activity, unseen: unseen),
                        lineWidth: activity != nil || unseen != nil || selected ? Theme.statusStroke : Theme.hairline)
            HStack(spacing: Theme.Space.s8) {
                Circle()
                    .fill(monitor.lastOutcome(component).map { Theme.color($0) } ?? Theme.line)
                    .frame(width: Theme.dotSize, height: Theme.dotSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(component.title)
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(activity?.label ?? last?.title ?? Strings.monitorQuiet)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.captionDigits)
                        .foregroundStyle(unseen == .error ? Theme.stop : Theme.blocked)
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            if let activity {
                WorkArc(activity: activity, now: now)
                    .frame(width: width, height: Theme.MonitorPanel.node.height)
            }
        }
        .frame(width: width, height: Theme.MonitorPanel.node.height)
        .contentShape(Rectangle())
        .help(last.map { "\($0.title)" } ?? component.title)
        .animation(Theme.Motion.color, value: unseen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.monitorNodeLabel(component.title, working: activity?.label, problems: count))
        .accessibilityAddTraits(.isButton)
    }

    private func stroke(activity: MonitorActivity?, unseen: Outcome?) -> Color {
        if let unseen { return Theme.color(unseen) }
        if activity != nil { return Theme.doing }
        return selected ? Theme.ink2 : Theme.line
    }
}

/// Work in progress: with a deadline, the share of it used so far, as the round ring does (DESIGN §6);
/// without one, a short arc that travels the outline until the work ends.
struct WorkArc: View {
    let activity: MonitorActivity
    let now: Date

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius)
        if let deadline = activity.deadline, deadline > activity.since {
            let used = now.timeIntervalSince(activity.since) / deadline.timeIntervalSince(activity.since)
            shape.trim(from: 0, to: min(1, max(0, used)))
                .stroke(used > 1 ? Theme.blocked : Theme.doing,
                        style: StrokeStyle(lineWidth: Theme.statusStroke, lineCap: .round))
        } else {
            let head = now.timeIntervalSince(activity.since).truncatingRemainder(dividingBy: Theme.MonitorPanel.sweepSeconds)
                / Theme.MonitorPanel.sweepSeconds
            shape.trim(from: head, to: min(1, head + 0.18))
                .stroke(Theme.doing, style: StrokeStyle(lineWidth: Theme.statusStroke, lineCap: .round))
        }
    }
}

// MARK: Inspector

struct MonitorRow: View {
    let event: MonitorEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s8) {
            Text(event.at.formatted(.dateTime.hour().minute().second()))
                .font(Theme.captionDigits)
                .foregroundStyle(Theme.ink2)
            Circle()
                .fill(Theme.color(event.outcome))
                .frame(width: Theme.MonitorPanel.rowDot, height: Theme.MonitorPanel.rowDot)
            Text(Strings.monitorRoute(event.from.title, event.to?.title))
                .font(Theme.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Text(event.title)
                .font(Theme.body)
                .foregroundStyle(event.outcome == .error ? Theme.stop : Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct MonitorDetail: View {
    let event: MonitorEvent?

    var body: some View {
        if let e = event {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    Text(e.title)
                        .font(Theme.title)
                        .foregroundStyle(e.outcome == .error ? Theme.stop : Theme.ink)
                        .textSelection(.enabled)
                    Text(Strings.monitorMeta(route: Strings.monitorRoute(e.from.title, e.to?.title),
                                             outcome: Strings.outcomeWord(e.outcome),
                                             at: e.at.formatted(date: .abbreviated, time: .standard), turn: e.turnID))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                    if !e.detail.isEmpty {
                        Text(e.detail)
                            .font(Theme.mono)
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(Strings.monitorPickEvent)
                .font(Theme.body)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .padding(Theme.Space.s16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
