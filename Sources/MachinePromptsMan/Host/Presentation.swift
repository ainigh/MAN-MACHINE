import Foundation
import MpmCore

/// What the views show, computed from the store and engine time. Pure, so it is tested on every
/// platform; the SwiftUI views only lay it out and pick colors (DESIGN §1 "exactness").

/// DESIGN §3 status tokens, by name. The UI maps each to a `Theme` color.
public enum Tone: String, Equatable, Sendable {
    case doing, next, done, blocked, stop, rest, neutral
}

public enum Countdown {
    /// Whole seconds left, rounded up: "0:00" appears only once the phase is over. The ring and the
    /// menu-bar digits both use this, so they agree to the second (DESIGN §11).
    public static func seconds(_ remaining: TimeInterval) -> Int {
        max(0, Int((remaining - 1e-9).rounded(.up)))
    }

    /// "4:32", "10:00", "72:05". Fits the reserved "00:00" width up to 99:59 (DESIGN §4).
    public static func digits(_ remaining: TimeInterval) -> String {
        let s = seconds(remaining)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public static let reservedDigits = "00:00"
}

public enum Phase {
    /// The full length of the phase the session is in, for the ring's fraction.
    public static func length(_ s: Session) -> TimeInterval? {
        let c = s.config
        switch s.state {
        case .work: return c.R
        case .timeUp: return c.G
        case .snooze: return c.snoozeLength
        case .status: return s.statusLength
        case .strategy: return c.strategyLength
        case .break: return c.Lb
        case .idle, .sitCheck, .end: return nil
        }
    }

    public static func remaining(_ s: Session, now: Date) -> TimeInterval {
        guard let end = s.phaseEnd else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// 1 at phase start, 0 at its end. Uses the same rounding as the digits, so they agree to the second.
    public static func fraction(_ s: Session, now: Date, continuous: Bool = true) -> Double {
        guard let len = length(s), len > 0 else { return 0 }
        let rem = remaining(s, now: now)
        let r = continuous ? rem : Double(Countdown.seconds(rem))
        return min(1, max(0, r / len))
    }

    /// DESIGN §6: the ring is drawn in the state color; STATUS reads as neutral, BREAK in `break`.
    public static func tone(_ state: SessionState) -> Tone {
        switch state {
        case .work, .snooze: return .doing
        case .timeUp: return .stop
        case .status: return .neutral
        case .strategy: return .next        // [default] strategy is about choosing N
        case .break: return .rest
        case .idle, .sitCheck, .end: return .neutral
        }
    }
}

/// DESIGN §4 menu bar: a ring that empties as the phase runs, a square while stopped, a dot in a break.
public struct MenuBarDisplay: Equatable, Sendable {
    public enum Glyph: Equatable, Sendable { case ring(Double), square, dot }
    public var glyph: Glyph
    public var tone: Tone
    public var digits: String?

    public static func make(_ session: Session?, now: Date) -> MenuBarDisplay {
        guard let s = session, s.state != .end, s.state != .idle else {
            return MenuBarDisplay(glyph: .square, tone: .neutral, digits: nil)
        }
        let digits = Countdown.digits(Phase.remaining(s, now: now))
        if s.state == .break { return MenuBarDisplay(glyph: .dot, tone: .rest, digits: digits) }
        return MenuBarDisplay(glyph: .ring(Phase.fraction(s, now: now, continuous: false)),
                              tone: Phase.tone(s.state), digits: digits)
    }
}

/// DESIGN §6 controls: exactly the events SPEC §6.8 allows in this state, nothing greyed out.
public enum SessionControl: Equatable, Sendable {
    case startSession
    case commit
    case finish
    case snooze(length: TimeInterval, left: Int)
    case stop
    case endSession
}

public struct SessionPaneDisplay: Equatable, Sendable {
    public var state: SessionState?
    public var round: Int?
    public var seated: TimeInterval
    public var remaining: TimeInterval
    public var ringFraction: Double
    public var tone: Tone
    public var controls: [SessionControl]
    /// STATUS only: "Away. Back in …" (DESIGN §6).
    public var awayFor: TimeInterval?
    /// STATUS and STRATEGY only.
    public var diff: [DiffLine]
    public var doing: Node?
    public var next: Node?

    public static func make(_ store: Store, now: Date) -> SessionPaneDisplay {
        let s = store.session.flatMap { $0.state == .end ? nil : $0 }
        var d = SessionPaneDisplay(state: s?.state, round: (s?.round ?? 0) > 0 ? s?.round : nil,
                                   seated: s?.seated(at: now) ?? 0, remaining: s.map { Phase.remaining($0, now: now) } ?? 0,
                                   ringFraction: s.map { Phase.fraction($0, now: now) } ?? 0,
                                   tone: s.map { Phase.tone($0.state) } ?? .neutral,
                                   controls: [], awayFor: nil, diff: [], doing: store.doing, next: store.next)
        guard let s else {
            d.controls = [.startSession]
            return d
        }
        switch s.state {
        case .idle, .strategy: d.controls = [.commit]
        case .work, .snooze: d.controls = [.finish]
        case .timeUp: d.controls = [.snooze(length: s.config.snoozeLength, left: max(0, s.config.zMax - s.z)), .stop]
        case .status, .break, .sitCheck, .end: d.controls = []
        }
        d.controls.append(.endSession)
        if s.state == .status { d.awayFor = d.remaining }
        if (s.state == .status || s.state == .strategy), let from = s.roundStart {
            d.diff = Metrics.roundDiff(in: store, from: from, to: now)
        }
        return d
    }
}

public enum CommitCheck: Equatable, Sendable {
    case ready
    /// One or both slots not chosen yet.
    case incomplete
    /// The engine's refusal (SPEC §6.5.1), shown in the tooltip (DESIGN §11).
    case refused(String)

    public static func evaluate(doing: NodeID?, next: NodeID?, store: Store) -> CommitCheck {
        guard let d = doing, let n = next else { return .incomplete }
        do { try Engine.validateCommit(d: d, n: n, store: store); return .ready } catch { return .refused("\(error)") }
    }
}
