import Foundation

/// SPEC §6.4
public enum SessionState: String, Codable, Equatable, Sendable {
    case idle, work, timeUp = "time_up", snooze, status, strategy, sitCheck = "sit_check", `break`, end

    /// SPEC §6.6.2 — states in which seated time accumulates.
    public var accumulatesSeated: Bool {
        switch self {
        case .work, .timeUp, .snooze, .status, .strategy: return true
        case .idle, .sitCheck, .break, .end: return false
        }
    }

    /// SPEC §13 #11 — states in which the model is silent.
    public var modelSilent: Bool {
        switch self {
        case .work, .timeUp, .snooze, .break: return true
        default: return false
        }
    }
}

/// SPEC §6.3
public struct Session: Codable, Equatable, Sendable {
    public var id: String
    public var startedAt: Date
    public var state: SessionState
    public var round: Int
    public var roundStart: Date?
    public var z: Int
    public var x: Int?
    public var statusLength: TimeInterval?
    public var phaseEnd: Date?
    public var sensorInactive: Bool
    /// Seated time folded in so far, plus when the current accumulation began (nil when not accumulating).
    public var seatedBase: TimeInterval
    public var seatedSince: Date?
    public var idleSince: Date?
    /// The config this session runs on. Settings changes apply at the next start_session (SPEC §11).
    public var config: SessionConfig

    public init(id: String, startedAt: Date, config: SessionConfig) {
        self.id = id; self.startedAt = startedAt; self.state = .idle; self.round = 0
        self.roundStart = nil; self.z = 0; self.x = nil; self.statusLength = nil; self.phaseEnd = nil
        self.sensorInactive = false; self.seatedBase = 0; self.seatedSince = nil; self.idleSince = startedAt
        self.config = config
    }

    /// Continuous seated time at `now`.
    public func seated(at now: Date) -> TimeInterval {
        seatedBase + (seatedSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func resetSeated(at now: Date) {
        seatedBase = 0
        seatedSince = state.accumulatesSeated ? now : nil
    }

    /// Moves to `state`, keeping the seated clock right. Does not schedule anything.
    mutating func enter(_ new: SessionState, at now: Date) {
        if state == .idle, new != .idle, let since = idleSince, now.timeIntervalSince(since) >= config.Lb {
            resetSeated(at: now)                    // SPEC §6.6.2: long idle resets
        }
        if state.accumulatesSeated && !new.accumulatesSeated {
            seatedBase = seated(at: now); seatedSince = nil
        } else if !state.accumulatesSeated && new.accumulatesSeated {
            seatedSince = now
        }
        idleSince = (new == .idle) ? now : nil
        state = new
    }
}
