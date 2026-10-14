import Foundation
import Observation
import MpmCore

/// A `say` shown in the held card (DESIGN §6). Cleared at commit.
public struct CardSay: Identifiable, Equatable, Sendable {
    public let id: Int
    public let turnID: String
    public let text: String
}

/// SPEC §8: one turn at a time, a phase turn per round at STATUS entry with STATUS end as its deadline,
/// output held until STRATEGY, message and answer turns only in STRATEGY or outside a session, late
/// output handled per SPEC §16 #17, and every turn and disposition in the turn log.
@MainActor
@Observable
public final class ModelTurnCoordinator: ModelTurnCoordinating {
    public weak var controller: SessionController?
    public private(set) var card: [CardSay] = []
    /// True while a turn is running. The pane may show a quiet indicator, never during WORK.
    public private(set) var busy = false
    /// Set when a `message` or `answer` turn failed (SPEC §8.7: tell the human only then).
    public private(set) var failure: String?
    public var settings: ModelSettings

    /// A late phase turn may still deliver a patch; it is abandoned this long after its deadline. [default]
    public static let lateLimit: TimeInterval = 300
    /// Real-time cap for message, answer, initiative and schedule turns. [default]
    public static let freeTurnLimit: TimeInterval = 120

    /// Model `next` requests go to the scheduler (task 08), which applies the attention policy.
    @ObservationIgnored public var onNext: ((Date, String) -> Void)?
    /// Runs a deferred trigger after the session ends (task 08).
    @ObservationIgnored public var onSessionEnded: (() -> Void)?

    @ObservationIgnored private var adapter: ModelAdapter
    @ObservationIgnored private var realNow: @Sendable () -> Date
    @ObservationIgnored private var current: Running?
    @ObservationIgnored private var queued: [Trigger] = []
    @ObservationIgnored private var heldTurnIDs: [String] = []
    @ObservationIgnored private var nextCardID = 0

    private struct Running {
        let turnID: String
        let trigger: Trigger
        let engineDeadline: Date?
        let round: Int?
        /// Real time, for the latency of a turn closed by `abandon`.
        let started: Date
        /// Real time by which the adapter was told to give up.
        var realLimit = Date.distantFuture
        var missed = false
        var task: Task<Void, Never>?
        var timers: [Cancellable] = []
    }

    public init(adapter: ModelAdapter = NullAdapter(), settings: ModelSettings = ModelSettings(),
                realNow: @escaping @Sendable () -> Date = { Date() }) {
        self.adapter = adapter
        self.settings = settings
        self.realNow = realNow
    }

    public func setAdapter(_ adapter: ModelAdapter, settings: ModelSettings) {
        self.adapter = adapter
        self.settings = settings
    }

    public var hasModel: Bool { !(adapter is NullAdapter) }

    // MARK: ModelTurnCoordinating (effects from the engine)

    public func startPhaseTurn(deadline: Date) {
        guard let c = controller else { return }
        let hits = InitiativeRules.evaluate(c.store, now: c.now())   // folded into the phase projection (SPEC §8.1)
        start(.phase, engineDeadline: deadline, hits: hits)
    }

    public func renderHeld() {
        guard let c = controller else { return }
        let held = c.store.held
        let ids = heldTurnIDs
        heldTurnIDs = []
        if !held.isEmpty {
            c.updateModelState("render \(held.count) held envelope(s) at STRATEGY") { $0.held = [] }
            // `held` is persisted, the ids are not: envelopes held before a relaunch come first and have none.
            let unknown = max(0, held.count - ids.count)
            for (i, env) in held.enumerated() { render(env, turnID: i < unknown ? "held" : ids[i - unknown]) }
        }
        drainQueue()
    }

    public func expireProposals() {
        guard let c = controller else { return }
        card = []
        let now = c.now()
        // SPEC §16 #16: expire silently, never as declined. A question asked for this STRATEGY expires with it.
        c.updateModelState("proposals expired at commit") { s in
            s.pending = []
            if let q = s.question, q.expiresAt <= now.addingTimeInterval(1e-6) || s.session != nil { s.question = nil }
        }
    }

    public func sessionEnded() {
        card = []
        onSessionEnded?()
        drainQueue()
    }

    // MARK: Intents from the person

    /// A typed or spoken message. Routed as `answer` while a question is pending (SPEC §8.4). Runs now in
    /// STRATEGY, IDLE or with no session; otherwise held for the next STRATEGY (SPEC §8.1).
    public func send(message text: String) {
        guard let c = controller else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        failure = nil
        expireQuestion(c)
        let trigger: Trigger = c.store.question != nil ? .answer(t) : .message(t)
        c.monitor.emit(.man, to: .coordinator, .info, trigger.kind, detail: t, at: c.now())
        if Self.mayRunFreeTurn(c.state) && current == nil {
            start(trigger, engineDeadline: nil, hits: [])
        } else {
            queued.append(trigger)
            c.log(.policy, "\(trigger.kind) queued until STRATEGY or the end of the session")
        }
    }

    /// An initiative or schedule trigger that already passed the attention policy (task 08).
    public func run(_ trigger: Trigger) {
        guard let c = controller else { return }
        guard c.state == nil, current == nil else {
            queued.append(trigger)
            return
        }
        start(trigger, engineDeadline: nil, hits: [])
    }

    static func mayRunFreeTurn(_ state: SessionState?) -> Bool {
        state == nil || state == .strategy || state == .idle
    }

    // MARK: Proposal disposition (SPEC §5.2–5.3, §8.5)

    public enum DispositionError: Error, Equatable, CustomStringConvertible {
        case unknownProposal
        case staleOp(NodeID)
        public var description: String {
            switch self {
            case .unknownProposal: return "that proposal is gone"
            case .staleOp(let id): return "\(id) changed since this was proposed"
            }
        }
    }

    /// Nodes changed since the proposal was made, from the patch log (SPEC §5.3).
    public func changedNodes(since p: Proposal) -> Set<NodeID> {
        guard let c = controller else { return [] }
        var out = Set<NodeID>()
        // Patches made by accepting part of this same proposal are not changes to it.
        for e in c.store.patchLog where e.at > p.at && !(e.author == .model && e.turnID == p.turnID) {
            for case .setNode(let n) in e.inverse { out.insert(n.id) }
            for op in e.ops { out.formUnion(op.touchedIDs) }
            out.formUnion(e.assignedIDs.values)
        }
        return out
    }

    public func isStale(_ p: Proposal) -> Bool {
        !changedNodes(since: p).intersection(OpSummary.existingIDs(p.ops, in: controller?.store ?? Store(now: .distantPast))).isEmpty
    }

    /// Accepts the whole proposal, or only `ops` (indices). Stale ops that touch changed nodes are blocked.
    public func accept(_ proposalID: String, ops indices: [Int]? = nil) throws {
        guard let c = controller, let p = c.store.pending.first(where: { $0.id == proposalID }) else {
            throw DispositionError.unknownProposal
        }
        let chosen = (indices ?? Array(p.ops.indices)).sorted().filter { p.ops.indices.contains($0) }
        let ops = chosen.map { p.ops[$0] }
        let changed = changedNodes(since: p)
        if let hit = OpSummary.existingIDs(ops, in: c.store).first(where: changed.contains) { throw DispositionError.staleOp(hit) }
        c.monitor.emit(.man, to: .coordinator, .info, "accept \(p.id)", detail: OpSummary.describe(ops, in: c.store),
                       turnID: p.turnID, at: c.now())
        let r = try c.apply(ops, author: .model, turnID: p.turnID)
        logDisposition(p, "accepted op(s) \(chosen) as patch \(r.entry.seq)")
        let remaining = p.ops.enumerated().filter { !chosen.contains($0.offset) }
            .map { OpSummary.resolving($0.element, r.entry.assignedIDs) }
        c.updateModelState("proposal \(p.id) accepted") { s in
            if remaining.isEmpty { s.pending.removeAll { $0.id == p.id } }
            else if let i = s.pending.firstIndex(where: { $0.id == p.id }) { s.pending[i].ops = remaining }
        }
    }

    /// Rejects the proposal and remembers it so the model does not repeat itself (SPEC §8.5).
    public func reject(_ proposalID: String) {
        guard let c = controller, let p = c.store.pending.first(where: { $0.id == proposalID }) else { return }
        let now = c.now()
        c.monitor.emit(.man, to: .coordinator, .info, "reject \(p.id)", detail: OpSummary.describe(p.ops, in: c.store),
                       turnID: p.turnID, at: now)
        let d = Declined(nodeIDs: OpSummary.existingIDs(p.ops, in: c.store), summary: OpSummary.describe(p.ops, in: c.store),
                         at: now, expiresAt: now.addingTimeInterval(Double(c.store.settings.declinedTTLDays) * 86_400))
        c.updateModelState("proposal \(p.id) rejected") { s in
            s.pending.removeAll { $0.id == p.id }
            s.declined.removeAll { $0.expiresAt <= now }
            s.declined.append(d)
        }
        logDisposition(p, "rejected")
    }

    /// Rejects and promotes the decline to a permanent `no_suggest` on the nodes it touched (SPEC §8.5).
    public func lock(_ proposalID: String) throws {
        guard let c = controller, let p = c.store.pending.first(where: { $0.id == proposalID }) else { return }
        let ids = OpSummary.existingIDs(p.ops, in: c.store).filter { $0 != c.store.rootID }
        reject(proposalID)
        let ops: [Op] = ids.compactMap { id in
            guard let n = c.store.nodes[id], !n.noSuggest else { return nil }
            return .updateNode(id: id, fields: NodeFields(flags: n.flags.union([Node.flagNoSuggest])))
        }
        if !ops.isEmpty { try c.apply(ops, author: .man) }
    }

    public func dismissCard() { card = [] }

    /// Waits for the running turn, and any it queued, to finish. For tests and orderly quit.
    public func waitUntilIdle() async {
        while let t = current?.task { await t.value }
    }

    // MARK: Running turns

    private func start(_ trigger: Trigger, engineDeadline: Date?, hits: [RuleHit]) {
        guard let c = controller else { return }
        guard current == nil else {
            if case .phase = trigger {
                c.log(.adapter, "phase turn skipped: another turn is still running")
                c.monitor.emit(.coordinator, .warning, "phase turn skipped", detail: "another turn is still running", at: c.now())
            } else {
                queued.append(trigger)
            }
            return
        }
        guard hasModel else {
            c.log(.adapter, "\(trigger.kind) trigger: no model configured")
            c.monitor.emit(.coordinator, .info, "\(trigger.kind) turn not started", detail: "No model is configured.", at: c.now())
            return
        }
        let turnID = "t_" + IDs.ulid(now: c.now()).dropFirst(2)
        expireQuestion(c)
        var store = c.store
        if case .answer = trigger {
            // The answer clears the slot; the projection still carries the question (SPEC §8.4).
            c.updateModelState("question answered") { $0.question = nil }
        }
        if case .initiative = trigger { } else { store.declined.removeAll { $0.expiresAt <= c.now() } }
        let realDeadline = engineDeadline.map { c.realDate(forEngine: $0) } ?? realNow().addingTimeInterval(Self.freeTurnLimit)
        let request = TurnRequest(turnID: turnID, trigger: trigger, store: store, now: c.now(), hits: hits,
                                  realDeadline: realDeadline, contextNote: settings.contextNote)
        var run = Running(turnID: turnID, trigger: trigger, engineDeadline: engineDeadline, round: c.store.session?.round,
                          started: realNow())
        let engine = TurnEngine(adapter: adapter, realNow: realNow)
        // A late phase turn keeps running past its deadline so a patch can still arrive (SPEC §16 #17).
        let adapterDeadline = engineDeadline.map { c.realDate(forEngine: $0.addingTimeInterval(Self.lateLimit)) } ?? realDeadline
        var adapterRequest = request
        adapterRequest.realDeadline = adapterDeadline
        run.realLimit = adapterDeadline
        busy = true
        c.log(.adapter, "turn \(turnID) started: \(trigger.kind)")
        c.monitor.begin(.model, trigger.kind, deadline: realDeadline)
        c.monitor.emit(.coordinator, to: .model, .info, "\(trigger.kind) turn", detail: "turn \(turnID)\nadapter \(adapter.name)\n" +
                       "deadline \(realDeadline.formatted(.iso8601)) (real time)", turnID: turnID, at: c.now())
        run.task = Task { [weak self] in
            let result = await engine.run(adapterRequest)
            self?.finish(turnID, result)
        }
        if let d = engineDeadline {
            run.timers.append(c.clock.schedule(at: d) { [weak self] in self?.deadlinePassed(turnID) })
            run.timers.append(c.clock.schedule(at: d.addingTimeInterval(Self.lateLimit)) { [weak self] in self?.abandon(turnID) })
        } else {
            let cap = c.clock.now().addingTimeInterval(Self.freeTurnLimit * c.timeScale)
            run.timers.append(c.clock.schedule(at: cap) { [weak self] in self?.abandon(turnID) })
        }
        current = run
    }

    private func deadlinePassed(_ turnID: String) {
        guard current?.turnID == turnID else { return }
        current?.missed = true
        controller?.log(.adapter, "turn \(turnID) missed its deadline; output will be treated as late")
        if let c = controller {
            c.monitor.emit(.model, .warning, "deadline missed", detail: "Output from this turn will be treated as late (SPEC §16 #17).",
                           turnID: turnID, at: c.now())
        }
    }

    /// A model that never answers leaves a working app (CLAUDE.md hard rule 4).
    private func abandon(_ turnID: String) {
        guard let run = current, run.turnID == turnID else { return }
        run.task?.cancel()
        if let c = controller {
            c.monitor.emit(.coordinator, to: .model, .error, "turn abandoned", detail: "No answer within the turn's limit; cancelled.",
                           turnID: turnID, at: c.now())
        }
        // Cancelling is a request; an adapter that ignores it would hold `current` forever and every later
        // turn would queue or be skipped behind it. Once the adapter has had its whole real-time allowance,
        // close the turn here; anything it returns later is dropped. (Engine time can run ahead of real time,
        // as on a manual clock, and then the adapter is still within its allowance and may yet answer.)
        guard realNow() >= run.realLimit.addingTimeInterval(-1) else { return }
        finish(turnID, TurnResult(turnID: turnID, projection: "", prompt: "", raw: nil, repaired: false, step: nil,
                                  warnings: [], envelope: nil, validation: nil,
                                  error: "abandoned: no answer within the turn's limit",
                                  latency: realNow().timeIntervalSince(run.started)))
    }

    private func finish(_ turnID: String, _ r: TurnResult) {
        guard let run = current, run.turnID == turnID, let c = controller else { return }
        for t in run.timers { t.cancel() }
        current = nil
        busy = false

        let deadlineMet: Bool
        var outcome: String
        if case .phase = run.trigger {
            deadlineMet = !run.missed && c.state == .status && c.store.session?.round == run.round
        } else {
            deadlineMet = r.error == nil
        }

        if let env = r.envelope {
            outcome = deliver(env, turnID: turnID, trigger: run.trigger, onTime: deadlineMet)
            if let reason = r.validation { outcome += "; patch rejected: \(reason)" }
            if let next = env.next { onNext?(next, turnID) }
        } else if let e = r.error {
            outcome = "failed: \(e)"
            if Self.isConversational(run.trigger) { failure = e }
        } else {
            outcome = "empty"
        }
        c.log(.adapter, "turn \(turnID) closed: \(outcome)")
        let record = TurnLogRecord(
            at: c.now(), turnID: turnID, trigger: run.trigger.kind + " template \(PromptTemplate.version)",
            projection: r.projection, prompt: r.prompt, raw: r.raw, ladderStep: r.step?.rawValue,
            validation: r.validation ?? (r.warnings.isEmpty ? "ok" : r.warnings.joined(separator: "; ")),
            outcome: outcome + (r.repaired ? " (repair pass)" : ""), latencyMs: Int(r.latency * 1000),
            deadlineMet: deadlineMet)
        c.persistence?.appendTurn(record)
        c.monitor.end(.model)
        let health: Outcome = r.error != nil ? .error : (r.validation != nil || !deadlineMet || r.envelope == nil) ? .warning : .ok
        c.monitor.emit(.model, to: .coordinator, health, "\(run.trigger.kind) turn: \(outcome)",
                       detail: Self.describe(record), turnID: turnID, at: c.now())
        drainQueue()
    }

    /// SPEC §8.6. Returns the outcome for the turn log.
    private func deliver(_ env: Envelope, turnID: String, trigger: Trigger, onTime: Bool) -> String {
        guard let c = controller else { return "no controller" }
        switch trigger {
        case .phase:
            if onTime {
                hold(env, turnID: turnID, c)
                return "held for STRATEGY"
            }
            // Late: say discarded, ask dropped, patch kept as a proposal for the next STRATEGY (SPEC §16 #17).
            guard !env.patch.isEmpty else { return "late; discarded" }
            hold(Envelope(say: "", ask: nil, patch: env.patch, next: nil), turnID: turnID, c)
            return "late; say and ask dropped, patch kept for the next STRATEGY"
        case .message, .answer, .initiative, .schedule:
            if Self.mayRunFreeTurn(c.state) {
                render(env, turnID: turnID)
                return "rendered"
            }
            hold(env, turnID: turnID, c)
            return "held for STRATEGY"
        }
    }

    private func hold(_ env: Envelope, turnID: String, _ c: SessionController) {
        heldTurnIDs.append(turnID)
        c.monitor.emit(.coordinator, to: .store, .info, "held until STRATEGY", turnID: turnID, at: c.now())
        c.updateModelState("turn \(turnID) held") { $0.held.append(env) }
    }

    /// Shows model output now. Only reachable in STRATEGY or outside a session (SPEC §13 #11).
    private func render(_ env: Envelope, turnID: String) {
        guard let c = controller else { return }
        precondition(!(c.store.session.map { $0.state.modelSilent && $0.state != .end } ?? false),
                     "model output rendered in a silent state")
        let now = c.now()
        c.monitor.emit(.coordinator, to: .output, .ok, "shown", detail: [env.say, env.ask.map { "ask: \($0)" } ?? "",
                       env.patch.isEmpty ? "" : "\(env.patch.count) proposed op(s)"].filter { !$0.isEmpty }.joined(separator: "\n"),
                       turnID: turnID, at: now)
        if !env.say.isEmpty {
            nextCardID += 1
            card.append(CardSay(id: nextCardID, turnID: turnID, text: env.say))
        }
        // Only STRATEGY's `phaseEnd` is "this STRATEGY"; in IDLE it is left over from the phase before.
        let strategyEnd = c.store.session.flatMap { $0.state == .strategy ? $0.phaseEnd : nil }
        c.updateModelState("turn \(turnID) rendered") { s in
            if let ask = env.ask, !ask.isEmpty {
                // SPEC §8.4 / §16 #15: in a session it expires at the end of this STRATEGY (or is cleared at the
                // next commit from STRATEGY); otherwise at the next quiet-hours start.
                let expires = strategyEnd ?? Self.nextQuietStart(after: now, settings: s.settings)
                s.question = PendingQuestion(turnID: turnID, at: now, text: ask, expiresAt: expires)
            }
            if !env.patch.isEmpty {
                s.pending.append(Proposal(id: "p_" + IDs.ulid(now: now).dropFirst(2), turnID: turnID, at: now,
                                          ops: env.patch, say: env.say))
            }
        }
    }

    /// SPEC §8.4: answer or expiry clears the slot. Nothing fires at `expires_at`, so a lapsed question is
    /// cleared when the slot is next read; otherwise a message hours later would be routed as its answer.
    private func expireQuestion(_ c: SessionController) {
        guard let q = c.store.question, q.expiresAt <= c.now() else { return }
        c.updateModelState("question from turn \(q.turnID) expired") { $0.question = nil }
    }

    private func drainQueue() {
        guard let c = controller, current == nil, Self.mayRunFreeTurn(c.state) else { return }
        // Initiative and schedule wait for the session to end; a message behind them still runs now.
        guard let i = queued.firstIndex(where: { t in
            switch t {
            case .initiative, .schedule: return c.state == nil
            default: return true
            }
        }) else { return }
        start(queued.remove(at: i), engineDeadline: nil, hits: [])
    }

    private func logDisposition(_ p: Proposal, _ what: String) {
        guard let c = controller else { return }
        // SPEC §13 #7: every model-authored op in the patch log has its acceptance in the turn log.
        c.persistence?.appendTurn(TurnLogRecord(at: c.now(), turnID: p.turnID, trigger: "disposition",
                                                projection: "", prompt: "", raw: nil,
                                                validation: OpSummary.describe(p.ops, in: c.store),
                                                outcome: "proposal \(p.id) \(what)"))
        c.log(.policy, "proposal \(p.id) \(what)")
    }

    /// The turn-log record as the monitor's detail pane shows it (SPEC §12: "why did it say that").
    static func describe(_ r: TurnLogRecord) -> String {
        var parts = ["trigger: \(r.trigger)", "outcome: \(r.outcome)"]
        if let v = r.validation { parts.append("validation: \(v)") }
        if let s = r.ladderStep { parts.append("ladder step: \(s)") }
        if let l = r.latencyMs { parts.append("latency: \(l) ms") }
        if let d = r.deadlineMet { parts.append("deadline met: \(d ? "yes" : "no")") }
        if let raw = r.raw { parts.append("\nraw output:\n\(raw)") }
        if !r.prompt.isEmpty { parts.append("\nprompt:\n\(r.prompt)") }
        return parts.joined(separator: "\n")
    }

    static func isConversational(_ t: Trigger) -> Bool {
        switch t { case .message, .answer: return true; default: return false }
    }

    static func nextQuietStart(after now: Date, settings: Settings) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: settings.timezone) ?? .current
        let today = cal.date(bySettingHour: settings.quietHoursStart, minute: 0, second: 0, of: now) ?? now
        return today > now ? today : cal.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
