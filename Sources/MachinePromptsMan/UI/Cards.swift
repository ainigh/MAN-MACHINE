#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import MpmCore
import MpmHost

/// DESIGN §7: what pops up. Separate non-activating panels at floating level, on every space, so a
/// round can run with the window closed (tasks/04). Cards never fade out on their own except as listed.
@MainActor
final class CardsController {
    private unowned let model: AppModel
    private var timeUp: NSPanel?
    private var band: NSPanel?
    private var closeTask: Task<Void, Never>?
    private let timeUpState = TimeUpState()

    init(model: AppModel) { self.model = model }

    func handle(_ a: TimedAnnouncement) {
        switch a.announcement {
        case .timesUp:
            showTimeUp()
        case .snoozeAccepted:
            close(&timeUp)
        case .stop, .noSnoozesLeft, .tooLate:
            showStop()
        case .movementBreak:
            close(&timeUp)
            showBand()
        case .sittingClockReset, .roundStart:
            close(&band)
        case .statusStart, .strategyStart:
            if timeUpState.word == nil { close(&timeUp) }
        default:
            if model.controller.state == nil { close(&timeUp); close(&band) }
        }
    }

    // MARK: Time's up (320 × 180, centred on the main screen, grace bar, pulsing border)

    private func showTimeUp() {
        closeTask?.cancel()
        timeUpState.word = nil
        if timeUp == nil {
            timeUp = panel(size: Theme.timeUpCard, content: TimeUpCard(model: model, state: timeUpState))
        }
        center(timeUp!)
        timeUp?.orderFrontRegardless()
    }

    /// DESIGN §7: "Stop." in the same card with the `stop` border, closing after 2 s.
    private func showStop() {
        timeUpState.word = Strings.stopWord
        if timeUp == nil {
            timeUp = panel(size: Theme.timeUpCard, content: TimeUpCard(model: model, state: timeUpState))
            center(timeUp!)
        }
        timeUp?.orderFrontRegardless()
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Motion.stopCardHold)
            guard !Task.isCancelled, let self else { return }
            self.close(&self.timeUp)
            self.timeUpState.word = nil
        }
    }

    // MARK: Movement break band (full width, top of the screen)

    private func showBand() {
        guard let screen = NSScreen.main else { return }
        let height: CGFloat = 44
        let frame = NSRect(x: screen.frame.minX, y: screen.visibleFrame.maxY - height, width: screen.frame.width, height: height)
        if band == nil {
            band = panel(size: frame.size, content: BreakBand(controller: model.controller))
            band?.ignoresMouseEvents = true                   // blocks nothing (SPEC §16 #13)
        }
        band?.setFrame(frame, display: true)
        band?.orderFrontRegardless()
    }

    // MARK: Panels

    private func panel<V: View>(size: CGSize, content: V) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false                                   // DESIGN §4: hairlines, not shadows
        p.becomesKeyOnlyIfNeeded = true
        p.contentView = NSHostingView(rootView: content)
        return p
    }

    private func center(_ p: NSPanel) {
        guard let s = NSScreen.main?.visibleFrame else { return }
        p.setFrameOrigin(NSPoint(x: s.midX - p.frame.width / 2, y: s.midY - p.frame.height / 2))
    }

    private func close(_ p: inout NSPanel?) {
        p?.orderOut(nil)
        p = nil
    }
}

@MainActor
@Observable
final class TimeUpState {
    /// nil while asking; "Stop." once stopped (by the person, by refusal, or by the grace window lapsing).
    var word: String?
}

struct TimeUpCard: View {
    let model: AppModel
    let state: TimeUpState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = model.controller
        TimelineView(.animation(minimumInterval: nil, paused: state.word != nil)) { ctx in
            let session = c.store.session
            let grace = session?.config.G ?? 10
            let asking: Bool = state.word == nil && c.state == .timeUp
            let end: Date = session?.phaseEnd ?? c.now()
            let remaining: Double = asking ? max(0, end.timeIntervalSince(c.now())) : 0
            let barFraction: Double = grace > 0 ? remaining / grace : 0
            let phase: Double = ctx.date.timeIntervalSinceReferenceDate * 2 * Double.pi
            // The one pulse (DESIGN §5): the border, once per second, during the grace window.
            let pulse: Double = state.word == nil ? 0.5 + 0.5 * Foundation.cos(phase) : 1
            VStack(spacing: Theme.Space.s16) {
                Text(state.word ?? Strings.timesUpTitle)
                    .font(Theme.heading)
                    .foregroundStyle(state.word == nil ? Theme.ink : Theme.stop)
                if state.word == nil, let s = session {
                    HStack(spacing: Theme.Space.s12) {
                        Button(Strings.snooze(s.config.snoozeLength, left: max(0, s.config.zMax - s.z))) { c.send(.snooze) }
                            .buttonStyle(.borderedProminent)
                            .monospacedDigit()
                        Button(Strings.stop) { c.send(.stop) }
                            .buttonStyle(.bordered)
                            .tint(Theme.stop)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(Theme.stop.opacity(reduceMotion ? 1 : 0.4 + 0.6 * pulse), lineWidth: Theme.statusStroke)
            )
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.stop)
                        .frame(width: geo.size.width * CGFloat(barFraction), height: Theme.graceBar)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(.horizontal, Theme.cardRadius)
            }
        }
        .frame(width: Theme.timeUpCard.width, height: Theme.timeUpCard.height)
    }
}

struct BreakBand: View {
    let controller: SessionController

    var body: some View {
        TimelineView(.periodic(from: .now, by: controller.testMode ? 1.0 / 60 : 1)) { _ in
            HStack(spacing: Theme.Space.s12) {
                Text(Strings.stateName(.break)).font(Theme.caption)
                Text(Strings.breakBody).font(Theme.body)
                Text(Countdown.digits(controller.remainingInPhase)).font(Theme.digits)
            }
            .foregroundStyle(Theme.onFill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.rest)
        }
    }
}
#endif
