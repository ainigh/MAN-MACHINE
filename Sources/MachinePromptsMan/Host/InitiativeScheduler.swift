import Foundation
import Observation
import MpmCore

/// Outside a session the machine still prompts the man, within policy (tasks/08, SPEC §8.2–8.3).
/// Rules decide *that*; the attention policy decides *when*; the model decides *how to say it*.
@MainActor
@Observable
public final class InitiativeScheduler {
    /// tasks/08: evaluate the rules every 15 minutes and at launch.
    public static let interval: TimeInterval = 15 * 60
    /// Hits arriving within this window become one trigger (SPEC §8.3 coalescing). [default]
    public static let coalesceWindow: TimeInterval = 60

    public private(set) var settings: HostSettings
    /// The latest policy decision, for the Schedule view.
    public private(set) var lastDecision: String?

    @ObservationIgnored public weak var controller: SessionController?
    @ObservationIgnored public weak var coordinator: ModelTurnCoordinator?
    @ObservationIgnored private let persistence: Persistence?
    @ObservationIgnored private var pendingHits: [[RuleHit]] = []
    @ObservationIgnored private var fireToken: Cancellable?
    @ObservationIgnored private var evalToken: Cancellable?
    @ObservationIgnored private var scheduleToken: Cancellable?
    @ObservationIgnored private var deferredSchedule: [ScheduleEntry] = []

    public init(controller: SessionController, coordinator: ModelTurnCoordinator?, persistence: Persistence?,
                settings: HostSettings) {
        self.controller = controller
        self.coordinator = coordinator
        self.persistence = persistence
        self.settings = settings
        controller.patchObservers.append { [weak self] r in
            guard let self, !r.unblocked.isEmpty else { return }
            self.evaluate(extra: r.unblocked.map { RuleHit.hit("unblocked", $0) })
        }
        controller.announcementObservers.append { [weak self] a in
            if a.announcement == .sessionOpen { self?.sessionStarted() }
        }
        coordinator?.onNext = { [weak self] date, turnID in self?.modelAskedNext(date, turnID: turnID) }
        coordinator?.onSessionEnded = { [weak self] in self?.sessionEnded() }
    }

    public func start() {
        evaluate()
        planSchedule()
    }

    public func update(_ f: (inout HostSettings) -> Void) {
        f(&settings)
        persistence?.saveHostSettings(settings)
    }

    // MARK: Initiative

    /// Evaluates the rules and queues new hits. During a session nothing wakes the model; the hits show up
    /// in the next phase projection instead (SPEC §8.1).
    public func evaluate(extra: [RuleHit] = []) {
        guard let c = controller else { return }
        let now = c.now()
        evalToken?.cancel()
        evalToken = c.clock.schedule(at: now.addingTimeInterval(Self.interval)) { [weak self] in self?.evaluate() }
        guard !c.sessionActive else { return }
        let hits = (InitiativeRules.evaluate(c.store, now: now) + extra).filter { h in
            !settings.disabledRules.contains(h.rule)
                && (settings.nodeSnoozes[h.nodeID].map { $0 <= now } ?? true)
                && !(settings.lastNudged[key(h)].map { AttentionPolicy.sameLocalDay($0, now, settings: c.store.settings) } ?? false)
        }
        guard !hits.isEmpty else { return }
        pendingHits.append(hits)
        if fireToken == nil {
            fireToken = c.clock.schedule(at: now.addingTimeInterval(Self.coalesceWindow)) { [weak self] in self?.fireInitiative() }
        }
    }

    private func fireInitiative() {
        fireToken = nil
        guard let c = controller, !pendingHits.isEmpty else { return }
        let now = c.now()
        let hits = AttentionPolicy.coalesce(pendingHits)
        switch decide(now) {
        case .run:
            pendingHits = []
            update { s in for h in hits { s.lastNudged[key(h)] = now } }
            note("initiative: run with \(hits.count) hit(s)")
            c.monitor.emit(.scheduler, to: .coordinator, .info, "initiative",
                           detail: hits.map { "\($0.rule) \($0.nodeID)" }.joined(separator: "\n"), at: now)
            coordinator?.run(.initiative(hits))
        case .defer(let until, let reason):
            note("initiative deferred until \(until.timeIntervalSince1970): \(reason)")
            fireToken = c.clock.schedule(at: until) { [weak self] in self?.fireInitiative() }
        case .deferToSessionEnd:
            pendingHits = []
            note("initiative folded into the next phase projection")
        case .suppress(let reason):
            pendingHits = []
            note("initiative suppressed: \(reason)")
        }
    }

    // MARK: Schedule

    /// One timer, for the earliest entry.
    public func planSchedule() {
        scheduleToken?.cancel()
        guard let c = controller, let first = c.store.schedule.min(by: { $0.at < $1.at }) else { return }
        let id = first.id
        scheduleToken = c.clock.schedule(at: max(first.at, c.now())) { [weak self] in self?.fireSchedule(id) }
    }

    public func addSchedule(at: Date, reason: String, source: ScheduleSource = .man) {
        guard let c = controller else { return }
        let e = ScheduleEntry(id: "s_" + IDs.ulid(now: c.now()).dropFirst(2), at: at, reason: reason, source: source)
        c.updateModelState("schedule \(e.id) added (\(source.rawValue))") { $0.schedule.append(e) }
        planSchedule()
    }

    public func removeSchedule(_ id: String) {
        controller?.updateModelState("schedule \(id) removed") { $0.schedule.removeAll { $0.id == id } }
        planSchedule()
    }

    private func fireSchedule(_ id: String) {
        guard let c = controller, let e = c.store.schedule.first(where: { $0.id == id }) else { planSchedule(); return }
        c.updateModelState("schedule \(id) fired") { $0.schedule.removeAll { $0.id == id } }
        dispatch(e)
        planSchedule()
    }

    private func dispatch(_ e: ScheduleEntry) {
        guard let c = controller else { return }
        switch decide(c.now()) {
        case .run:
            note("schedule \(e.id): run")
            c.monitor.emit(.scheduler, to: .coordinator, .info, "schedule", detail: e.reason, at: c.now())
            coordinator?.run(.schedule(source: e.source, reason: e.reason))
        case .defer(let until, let reason):
            note("schedule \(e.id) deferred: \(reason)")
            var moved = e; moved.at = until
            c.updateModelState("schedule \(e.id) deferred") { $0.schedule.append(moved) }
        case .deferToSessionEnd:
            note("schedule \(e.id) deferred to the end of the session")
            deferredSchedule.append(e)
        case .suppress(let reason):
            note("schedule \(e.id) suppressed: \(reason)")
        }
    }

    /// SPEC §8.3 model `next`, clamped, becomes a `source: model` entry.
    public func modelAskedNext(_ requested: Date, turnID: String) {
        guard let c = controller else { return }
        let s = c.store.session.flatMap { $0.state == .end ? nil : $0 }
        let nextStrategy: Date? = s.flatMap { s in
            switch s.state {
            case .status: return s.phaseEnd
            case .strategy: return c.now()
            default: return s.phaseEnd
            }
        }
        let at = AttentionPolicy.clampNext(requested, now: c.now(), settings: c.store.settings,
                                           sessionActive: s != nil, nextStrategyStart: nextStrategy)
        addSchedule(at: at, reason: "model asked to be consulted (turn \(turnID))", source: .model)
    }

    private func sessionStarted() {
        if settings.snoozedUntilNextSession { update { $0.snoozedUntilNextSession = false } }
        pendingHits = []
    }

    public func sessionEnded() {
        let deferred = deferredSchedule
        deferredSchedule = []
        for e in deferred { dispatch(e) }
        evaluate()
    }

    // MARK: Attention snooze (SPEC §8.3)

    public func snooze(until date: Date) { update { $0.snoozedUntil = date; $0.snoozedUntilNextSession = false } }
    public func snoozeUntilNextSession() { update { $0.snoozedUntilNextSession = true } }
    public func resume() {
        update { $0.snoozedUntil = nil; $0.snoozedUntilNextSession = false }
        evaluate()
    }
    public func setRule(_ rule: String, enabled: Bool) {
        update { if enabled { $0.disabledRules.remove(rule) } else { $0.disabledRules.insert(rule) } }
    }

    /// SPEC §8.3 "snooze a node": no initiative about this node until `date`; nil resumes.
    public func snooze(node id: NodeID, until date: Date?) {
        update { s in
            let now = controller?.now() ?? Date()
            s.nodeSnoozes = s.nodeSnoozes.filter { $0.value > now }        // drop lapsed entries while here
            s.nodeSnoozes[id] = date
        }
        if date == nil { evaluate() }
    }

    public func nodeSnoozed(_ id: NodeID) -> Bool {
        settings.nodeSnoozes[id].map { $0 > (controller?.now() ?? Date()) } ?? false
    }

    public var snoozedUntil: Date? { settings.snoozedUntil.flatMap { $0 > (controller?.now() ?? Date()) ? $0 : nil } }

    // MARK: Internals

    private func decide(_ now: Date) -> AttentionPolicy.Decision {
        guard let c = controller else { return .suppress(reason: "no controller") }
        let today = (persistence?.readTurnLog() ?? []).filter {
            ($0.trigger.hasPrefix("initiative") || $0.trigger.hasPrefix("schedule"))
                && AttentionPolicy.sameLocalDay($0.at, now, settings: c.store.settings)
        }.count
        return AttentionPolicy.decide(now: now, settings: c.store.settings, context: .init(
            sessionActive: c.sessionActive, snoozedUntil: settings.snoozedUntil,
            snoozedUntilNextSession: settings.snoozedUntilNextSession, nudgesToday: today))
    }

    private func note(_ s: String) {
        lastDecision = s
        controller?.log(.policy, s)
        if let c = controller { c.monitor.emit(.scheduler, .info, s, at: c.now()) }
    }

    private func key(_ h: RuleHit) -> String { h.rule + "|" + h.nodeID }

    public static let ruleNames = ["overdue", "due_soon", "stale", "unblocked", "drift"]
}
