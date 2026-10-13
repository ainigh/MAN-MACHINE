import Foundation

public enum TimerKind: Codable, Equatable, Sendable, Hashable {
    case reminder(remaining: TimeInterval)
    case roundEnd, grace, snoozeEnd, statusEnd, strategyEnd, breakEnd
}

/// SPEC §6.5 — inputs to the engine.
public enum Event: Equatable, Sendable {
    case startSession
    case commit(doing: NodeID, next: NodeID)
    case finish
    case snooze
    case stop
    case endSession
    case tick(TimerKind)
    case activity(idle: Bool)
}

/// What the host must do after a reduction. The engine itself never touches a clock, a screen or a model.
public enum Effect: Equatable, Sendable {
    case announce(Announcement)
    case schedule(TimerKind, at: Date)
    case cancelTimers
    case startModelTurn(deadline: Date)   // SPEC §8.1 `phase` trigger, once per round
    case renderHeld                       // SPEC §8.6, at STRATEGY start
    case expireProposals                  // SPEC §8.5, at commit
    case sessionEnded
}

/// SPEC §6. Every function is deterministic in (store, event, now).
public enum Engine {

    // MARK: Entry points

    /// Reduce one event. Patches go through `applyPatch`, not here.
    public static func handle(_ event: Event, store: inout Store, now: Date) -> [Effect] {
        if case .startSession = event {
            guard store.session == nil || store.session?.state == .end else { return [.announce(.notAvailable)] }
            var s = Session(id: IDs.ulid(now: now), startedAt: now, config: store.settings.session)
            s.state = .idle
            store.session = s
            return [.announce(.sessionOpen)]
        }
        guard var s = store.session, s.state != .end else { return [.announce(.notAvailable)] }
        var fx: [Effect] = []
        defer { store.session = s }

        switch (s.state, event) {

        case (.idle, .commit(let d, let n)):
            do {
                try commitPatch(d: d, n: n, store: &store, session: s, now: now)
            } catch { return [.announce(.refused("\(error)"))] }
            fx += startRound(store: &store, session: &s, now: now)

        case (.work, .tick(.reminder(let t))):
            fx.append(.announce(.reminder(remaining: t)))

        case (.work, .finish), (.snooze, .finish):
            fx += enterStatus(store: &store, session: &s, now: now, announce: nil)

        case (.work, .tick(.roundEnd)), (.snooze, .tick(.snoozeEnd)):
            s.enter(.timeUp, at: now)
            s.phaseEnd = now.addingTimeInterval(s.config.G)
            fx += [.announce(.timesUp), .schedule(.grace, at: s.phaseEnd!)]

        case (.timeUp, .snooze):
            if s.z < s.config.zMax {
                s.z += 1
                s.enter(.snooze, at: now)
                s.phaseEnd = now.addingTimeInterval(s.config.snoozeLength)
                fx += [.cancelTimers,
                       .announce(.snoozeAccepted(z: s.z, zMax: s.config.zMax, length: s.config.snoozeLength)),
                       .schedule(.snoozeEnd, at: s.phaseEnd!)]
            } else {
                fx += enterStatus(store: &store, session: &s, now: now, announce: .noSnoozesLeft)
            }

        case (.timeUp, .stop), (.timeUp, .tick(.grace)):
            fx += enterStatus(store: &store, session: &s, now: now, announce: .stop)

        case (.status, .snooze):
            fx.append(.announce(.tooLate))

        case (.status, .tick(.statusEnd)):
            if let len = s.statusLength, len >= s.config.Lb, !s.sensorInactive { s.resetSeated(at: now) }   // SPEC §6.6.2
            s.enter(.strategy, at: now)
            s.phaseEnd = now.addingTimeInterval(s.config.strategyLength)
            fx += [.announce(.strategyStart(length: s.config.strategyLength)), .renderHeld,
                   .schedule(.strategyEnd, at: s.phaseEnd!)]

        case (.strategy, .commit(let d, let n)):
            do {
                try commitPatch(d: d, n: n, store: &store, session: s, now: now)
            } catch { return [.announce(.refused("\(error)"))] }
            fx.append(.expireProposals)
            fx += sitCheck(store: &store, session: &s, now: now)

        case (.strategy, .tick(.strategyEnd)):
            fx.append(.expireProposals)
            fx += autoCommit(store: &store, session: &s, now: now)

        case (.break, .tick(.breakEnd)):
            s.resetSeated(at: now)
            fx.append(.announce(.sittingClockReset))
            fx += startRound(store: &store, session: &s, now: now)

        case (_, .endSession):
            s.enter(.end, at: now)
            fx += [.cancelTimers, .sessionEnded]

        case (_, .activity(let idle)):
            s.sensorInactive = idle

        case (_, .tick):
            break   // a stale timer; ignore silently

        default:
            fx.append(.announce(.notAvailable))
        }
        return fx
    }

    /// Apply a patch, then let the session react: commit-by-patch (§6.5 note) and vacancies (§6.7).
    @discardableResult
    public static func applyPatch(_ ops: [Op], author: Author, store: inout Store, now: Date,
                                  base: Int? = nil, turnID: String? = nil) throws -> (ApplyResult, [Effect]) {
        let before = (store.doing?.id, store.next?.id)
        let result = try store.apply(ops, author: author, now: now, base: base, turnID: turnID)
        guard var s = store.session, s.state != .end else { return (result, []) }
        var fx: [Effect] = []
        defer { store.session = s }
        let after = (store.doing?.id, store.next?.id)
        let slotsTouched = before != after

        switch s.state {
        case .idle, .strategy:
            if slotsTouched, after.0 != nil, after.1 != nil {
                if s.state == .strategy { fx.append(.expireProposals); fx += sitCheck(store: &store, session: &s, now: now) }
                else { fx += startRound(store: &store, session: &s, now: now) }
            }
        case .work, .snooze, .timeUp:
            if after.0 == nil, before.0 != nil {
                if let n = store.next {
                    _ = try? store.apply([.setStatus(n.id, .doing)], author: .system, now: now)
                    fx.append(.announce(.nowDoing(n.title)))
                } else {
                    fx.append(.announce(.noDoingNode))
                }
            }
        default: break
        }
        return (result, fx)
    }

    // MARK: Transitions

    static func commitPatch(d: NodeID, n: NodeID, store: inout Store, session: Session, now: Date) throws {
        try validateCommit(d: d, n: n, store: store)
        var ops: [Op] = []
        if store.nodes[d]?.status != .doing { ops.append(.setStatus(d, .doing)) }
        if store.nodes[n]?.status != .next { ops.append(.setStatus(n, .next)) }
        if !ops.isEmpty { try store.apply(ops, author: .man, now: now) }
    }

    /// SPEC §6.5.1
    public static func validateCommit(d: NodeID, n: NodeID, store: Store) throws {
        guard let D = store.nodes[d] else { throw ValidationError.unknownNode(d) }
        guard let N = store.nodes[n] else { throw ValidationError.unknownNode(n) }
        if d == n { throw ValidationError.depOnSelf(d) }
        if !D.status.isLive { throw ValidationError.doingOnUnavailable(d, D.status) }
        if !store.unfinishedDeps(of: d).isEmpty { throw ValidationError.openWithUnfinishedDeps(d) }
        if N.status.isFinished { throw ValidationError.nextOnUnavailable(n, N.status) }
        if N.status == .blocked {
            let unfinished = store.unfinishedDeps(of: n)
            if !(unfinished.count == 1 && unfinished.first == d) { throw ValidationError.nextOnUnavailable(n, N.status) }
        }
    }

    static func startRound(store: inout Store, session s: inout Session, now: Date) -> [Effect] {
        s.round += 1
        s.roundStart = now
        s.z = 0
        s.x = nil
        s.statusLength = nil
        s.sensorInactive = false
        s.enter(.work, at: now)
        let R = s.config.R
        s.phaseEnd = now.addingTimeInterval(R)
        var fx: [Effect] = [.cancelTimers,
                            .announce(.roundStart(round: s.round, doing: store.doing?.title, next: store.next?.title, R: R))]
        for rem in s.config.reminders where rem < R {
            fx.append(.schedule(.reminder(remaining: rem), at: now.addingTimeInterval(R - rem)))
        }
        fx.append(.schedule(.roundEnd, at: s.phaseEnd!))
        return fx
    }

    static func enterStatus(store: inout Store, session s: inout Session, now: Date, announce: Announcement?) -> [Effect] {
        let from = s.roundStart ?? now
        let x = Metrics.x(in: store, from: from, to: now)
        let len = s.config.statusLength(z: s.z, x: x)
        s.x = x
        s.statusLength = len
        s.sensorInactive = false
        s.enter(.status, at: now)
        s.phaseEnd = now.addingTimeInterval(len)
        var fx: [Effect] = [.cancelTimers]
        if let a = announce { fx.append(.announce(a)) }
        fx += [.announce(.statusStart(roundElapsed: now.timeIntervalSince(from), length: len, z: s.z, x: x,
                                      diff: Metrics.roundDiff(in: store, from: from, to: now))),
               .startModelTurn(deadline: s.phaseEnd!),
               .schedule(.statusEnd, at: s.phaseEnd!)]
        return fx
    }

    static func sitCheck(store: inout Store, session s: inout Session, now: Date) -> [Effect] {
        s.enter(.sitCheck, at: now)
        let seated = s.seated(at: now)
        if seated + s.config.R > s.config.Ls {
            s.enter(.break, at: now)
            s.phaseEnd = now.addingTimeInterval(s.config.Lb)
            return [.cancelTimers, .announce(.movementBreak(seated: seated, length: s.config.Lb)),
                    .schedule(.breakEnd, at: s.phaseEnd!)]
        }
        return [.announce(.continue(seated: seated))] + startRound(store: &store, session: &s, now: now)
    }

    /// SPEC §6.7 last two rows: keep D if still doing; else promote N; else oldest open. N: oldest open ≠ D.
    static func autoCommit(store: inout Store, session s: inout Session, now: Date) -> [Effect] {
        let d: Node? = store.doing ?? store.next ?? store.oldestOpen
        guard let D = d else {
            s.enter(.idle, at: now)
            return [.cancelTimers, .announce(.noOpenNodes)]
        }
        let N: Node? = (store.next?.id == D.id ? nil : store.next) ?? store.nodes.values
            .filter { $0.status == .open && $0.id != D.id && $0.id != store.rootID }
            .min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        var ops: [Op] = []
        if D.status != .doing { ops.append(.setStatus(D.id, .doing)) }
        if let N, N.status != .next { ops.append(.setStatus(N.id, .next)) }
        do { if !ops.isEmpty { try store.apply(ops, author: .system, now: now) } } catch {
            s.enter(.idle, at: now)
            return [.cancelTimers, .announce(.refused("\(error)"))]
        }
        return [.announce(.autoCommit(doing: store.doing?.title, next: store.next?.title))]
            + sitCheck(store: &store, session: &s, now: now)
    }
}
