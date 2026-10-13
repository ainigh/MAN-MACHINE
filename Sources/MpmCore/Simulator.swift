import Foundation

/// Drives `Engine` against a virtual clock. The host app does the same thing with real timers;
/// this is the reference behaviour it must match. Every effect is recorded.
public struct Simulator {
    public var store: Store
    public var now: Date
    public private(set) var timers: [(TimerKind, Date)] = []
    public private(set) var announcements: [(Date, Announcement)] = []
    public private(set) var effects: [(Date, Effect)] = []
    /// Session state right after each effect was emitted, parallel to `effects`.
    public private(set) var effectStates: [SessionState?] = []

    public init(store: Store, now: Date) { self.store = store; self.now = now }

    public var state: SessionState? { store.session?.state }

    public mutating func send(_ e: Event) {
        absorb(Engine.handle(e, store: &store, now: now))
    }

    @discardableResult
    public mutating func patch(_ ops: [Op], author: Author = .man) throws -> ApplyResult {
        let (r, fx) = try Engine.applyPatch(ops, author: author, store: &store, now: now)
        absorb(fx)
        return r
    }

    /// Advance the clock, firing timers in order as they come due.
    public mutating func advance(_ seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let i = timers.indices.min(by: { timers[$0].1 < timers[$1].1 }), timers[i].1 <= target {
            let (kind, at) = timers.remove(at: i)
            now = at
            send(.tick(kind))
        }
        now = target
    }

    /// Advance until the session reaches `state` (or give up after `limit` seconds).
    public mutating func advance(until state: SessionState, limit: TimeInterval = 86_400) {
        let deadline = now.addingTimeInterval(limit)
        while self.state != state, now < deadline {
            guard let next = timers.map(\.1).min() else { return }
            advance(min(next, deadline).timeIntervalSince(now))
        }
    }

    private mutating func absorb(_ fx: [Effect]) {
        for f in fx {
            effects.append((now, f)); effectStates.append(store.session?.state)
            switch f {
            case .announce(let a): announcements.append((now, a))
            case .schedule(let k, let at): timers.append((k, at))
            case .cancelTimers: timers.removeAll()
            default: break
            }
        }
    }

    public func transcript() -> String {
        let t0 = store.session?.startedAt ?? announcements.first?.0 ?? now
        return announcements.map { (d, a) in
            "[\(Announcement.fmt(d.timeIntervalSince(t0)))]  A: \(a.text)"
        }.joined(separator: "\n")
    }
}
