#if os(macOS)
import SwiftUI
import MpmCore
import MpmHost

/// DESIGN §6: the clock. Header, ring, slots, controls, announcement line, round diff, held output.
struct SessionPaneView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var controller: SessionController { model.controller }

    var body: some View {
        // The ring sweeps continuously (DESIGN §5); nothing ticks when nothing is counting.
        TimelineView(.animation(minimumInterval: nil, paused: !controller.sessionActive)) { _ in
            content(SessionPaneDisplay.make(controller.store, now: controller.now()))
        }
    }

    @ViewBuilder
    private func content(_ d: SessionPaneDisplay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            reminderStrip
            VStack(alignment: .leading, spacing: Theme.Space.s16) {
                header(d)
                RingView(fraction: d.ringFraction, tone: d.tone, digits: d.state == nil ? nil : Countdown.digits(d.remaining),
                         label: d.state.map { Strings.stateName($0) } ?? Strings.stateName(nil))
                    .frame(maxWidth: .infinity)
                slots(d)
                controls(d)
                announcementLine
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s16) {
                        if !d.diff.isEmpty { RoundDiffView(diff: d.diff) }
                        if d.state == nil || d.state == .strategy || d.state == .idle {
                            HeldCardView(model: model)
                        }
                    }
                }
                .scrollIndicators(.never)
                Spacer(minLength: 0)
                if d.controls.contains(.endSession) {
                    Button(Strings.endSessionButton) { controller.send(.endSession) }
                        .buttonStyle(.plain)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.top, Theme.Space.s32)
            .padding(.bottom, Theme.Space.s16)
        }
        .animation(reduceMotion ? nil : Theme.Motion.layout, value: d.state)
    }

    // MARK: Pieces

    /// DESIGN §7 reminder: a thin strip at the top of the pane until the next state change. Status
    /// colors are strokes and dots, not fills (DESIGN §3), so the strip is a dot and a `doing` hairline.
    private var reminderStrip: some View {
        ZStack {
            if let a = controller.lastAnnouncement, case .reminder = a.announcement, a.state == controller.state {
                HStack(spacing: Theme.Space.s8) {
                    Circle().fill(Theme.doing).frame(width: Theme.dotSize, height: Theme.dotSize)
                    Text(a.text)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.s4)
                .padding(.horizontal, Theme.Space.s16)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.doing).frame(height: Theme.hairline) }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Theme.Motion.fade, value: controller.lastAnnouncement?.id)
    }

    private func header(_ d: SessionPaneDisplay) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Text(Strings.stateName(d.state))
                .font(Theme.caption)
                .foregroundStyle(Theme.ink2)
            Spacer()
            if let r = d.round {
                Text(Strings.round(r)).font(Theme.caption).foregroundStyle(Theme.ink2)
            }
            if d.state != nil {
                Text(Strings.seated(d.seated))
                    .font(Theme.captionDigits)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func slots(_ d: SessionPaneDisplay) -> some View {
        let store = controller.store
        let pickable = model.canPickSlots
        let doing = pickable ? model.commitDoing.flatMap { store.nodes[$0] } : d.doing
        let next = pickable ? model.commitNext.flatMap { store.nodes[$0] } : d.next
        return VStack(alignment: .leading, spacing: Theme.Space.s8) {
            SlotRow(label: Strings.doing, title: doing?.title, color: Theme.doing)
            SlotRow(label: Strings.next, title: next?.title, color: Theme.next)
        }
    }

    @ViewBuilder
    private func controls(_ d: SessionPaneDisplay) -> some View {
        if d.state == .status, let away = d.awayFor {
            Text(Strings.away(away))
                .font(Theme.body)
                .foregroundStyle(Theme.ink2)
                .monospacedDigit()
        } else if d.state == .break {
            Text(Strings.breakBody).font(Theme.body).foregroundStyle(Theme.rest)
        } else {
            HStack(spacing: Theme.Space.s8) {
                ForEach(Array(d.controls.enumerated()), id: \.offset) { _, c in
                    control(c)
                }
            }
        }
    }

    @ViewBuilder
    private func control(_ c: SessionControl) -> some View {
        switch c {
        case .startSession:
            Button(Strings.startSessionButton) { model.startSession() }
                .buttonStyle(.borderedProminent)
        case .commit:
            let check = model.commitCheck
            Button(Strings.commit) { model.commit() }
                .buttonStyle(.borderedProminent)
                .disabled(check != .ready)
                .help(commitHelp(check))
        case .finish:
            Button(Strings.finish) { controller.send(.finish) }
                .buttonStyle(.borderedProminent)
        case .snooze(let length, let left):
            Button(Strings.snooze(length, left: left)) { controller.send(.snooze) }
                .buttonStyle(.bordered)
                .monospacedDigit()
        case .stop:
            Button(Strings.stop) { controller.send(.stop) }
                .buttonStyle(.bordered)
                .tint(Theme.stop)
        case .endSession:
            EmptyView()
        }
    }

    private func commitHelp(_ c: CommitCheck) -> String {
        switch c {
        case .ready: return Strings.commit
        case .incomplete: return Strings.commitIncomplete
        case .refused(let why): return why
        }
    }

    /// DESIGN §6: the last announcement, replaced in place with a 120 ms fade. Engine wording, unchanged.
    private var announcementLine: some View {
        ZStack(alignment: .leading) {
            if let a = controller.lastAnnouncement {
                Text(a.text)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(a.id)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.fade, value: controller.lastAnnouncement?.id)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SlotRow: View {
    let label: String
    let title: String?
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Circle().fill(color).frame(width: Theme.dotSize, height: Theme.dotSize)
            Text(label).font(Theme.caption).foregroundStyle(Theme.ink2).frame(width: Theme.slotLabelWidth, alignment: .leading)
            Text(title ?? Strings.vacant)
                .font(Theme.body)
                .foregroundStyle(title == nil ? Theme.ink2 : Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}

/// DESIGN §6: 220 pt, 6 pt stroke in the state color, the countdown in the centre.
struct RingView: View {
    let fraction: Double
    let tone: Tone
    let digits: String?
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: Theme.ringStroke)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.color(tone), style: StrokeStyle(lineWidth: Theme.ringStroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text(digits ?? Strings.vacant)
                .font(Theme.countdown)
                .tracking(Theme.countdownTracking)
                .foregroundStyle(digits == nil ? Theme.ink2 : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: Theme.ringDiameter, height: Theme.ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(digits ?? Strings.vacant)
    }
}

struct RoundDiffView: View {
    let diff: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            ForEach(diff, id: \.id) { line in
                HStack(spacing: Theme.Space.s8) {
                    Text(line.title).font(Theme.body).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: Theme.Space.s8)
                    Text(Strings.diffRow(line)).font(Theme.caption).foregroundStyle(Theme.color(Tone.of(line.to)))
                }
            }
        }
    }
}

extension Tone {
    /// DESIGN §3: one accent per status.
    static func of(_ s: Status) -> Tone {
        switch s {
        case .doing: return .doing
        case .next: return .next
        case .done: return .done
        case .blocked: return .blocked
        case .open, .crossedOut: return .neutral
        }
    }
}
#endif
