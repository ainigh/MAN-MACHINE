import Foundation
import Observation
import MpmCore

public struct TimedAnnouncement: Identifiable, Equatable, Sendable {
    public let id: Int
    public let at: Date
    public let announcement: Announcement
    /// Session state once the reduction that produced this announcement finished.
    public let state: SessionState?
    /// Engine wording, never reworded by the UI (CLAUDE.md hard rule 6).
    public var text: String { announcement.text }
}

/// The one owner of the store (tasks/02). Every engine event and every patch goes through here; the
/// effects the engine returns become timers, announcements, model-coordinator calls, persistence and
/// system-log lines, in the order the engine emitted them. Views send intents; they never touch the store.
@MainActor
@Observable
public final class SessionController {
    public private(set) var store: Store
    public private(set) var announcements: [TimedAnnouncement] = []
    public private(set) var lastAnnouncement: TimedAnnouncement?
    /// Shared by the graph and the grid (tasks/06).
    public var selection: NodeID?
    public private(set) var testMode = false
    /// Engine-time instants of the timers currently planned. The UI reads the next reminder from here.
    public private(set) var plannedTimers: [TimerKind: Date] = [:]
    public private(set) var recentSystemLog: [SystemLogRecord] = []
    /// Nodes unblocked by the most recent patch (SPEC §8.2 `unblocked`), for the initiative scheduler.
    public private(set) var lastUnblocked: [NodeID] = []

    public static let announcementLimit = 50
    static let systemLogLimit = 200

    @ObservationIgnored public private(set) var clock: Clock
    @ObservationIgnored private let realClock: Clock
    @ObservationIgnored public let persistence: Persistence?
    @ObservationIgnored public var coordinator: ModelTurnCoordinating?
    /// Cards, sounds, notifications and speech subscribe here (tasks/04). Called after the store is updated.
    @ObservationIgnored public var announcementObservers: [@MainActor (TimedAnnouncement) -> Void] = []
    /// Called after every applied patch, e.g. to raise the `unblocked` initiative (SPEC §8.2).
    @ObservationIgnored public var patchObservers: [@MainActor (ApplyResult) -> Void] = []

    @ObservationIgnored private var timerTokens: [TimerKind: Cancellable] = [:]
    @ObservationIgnored private var plannedOrder: [TimerKind: Int] = [:]
    @ObservationIgnored private var planCounter = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nextAnnouncementID = 0
    @ObservationIgnored private var undoStack: [Int] = []
    @ObservationIgnored private var redoStack: [LogEntry] = []
    @ObservationIgnored private var undoRedoSeqs = Set<Int>()

    public init(store: Store, clock: Clock = SystemClock(), persistence: Persistence? = nil,
                coordinator: ModelTurnCoordinating? = nil) {
        self.store = store
        self.clock = clock
        self.realClock = clock
        self.persistence = persistence
        self.coordinator = coordinator
    }

    // MARK: Reading

    public var state: SessionState? { store.session.flatMap { $0.state == .end ? nil : $0.state } }
    public var sessionActive: Bool { state != nil }
    public func now() -> Date { clock.now() }

    /// Engine seconds per real second: 60 in test mode, else 1.
    public var timeScale: Double { (clock as? ScaledClock)?.factor ?? 1 }

    /// The real instant at which engine time reaches `date`, for adapter deadlines.
    public func realDate(forEngine date: Date) -> Date {
        Date().addingTimeInterval(date.timeIntervalSince(clock.now()) / timeScale)
    }

    public var seatedNow: TimeInterval { store.session?.seated(at: clock.now()) ?? 0 }

    public var remainingInPhase: TimeInterval {
        guard let end = store.session?.phaseEnd, sessionActive else { return 0 }
        return max(0, end.timeIntervalSince(clock.now()))
    }

    /// Remaining time at which the next reminder fires, if one is planned.
    public var nextReminder: TimeInterval? {
        plannedTimers.compactMap { if case .reminder(let t) = $0.key { return t } else { return nil } }.max()
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Events

    public func send(_ event: Event) {
        reduce(event, now: clock.now())
    }

    /// A patch from Man (or an accepted proposal, author `.model`). Throws the engine's refusal; nothing changes then.
    @discardableResult
    public func apply(_ ops: [Op], author: Author = .man, base: Int? = nil, turnID: String? = nil) throws -> ApplyResult {
        let r = try applyPatch(ops, author: author, base: base, turnID: turnID, now: clock.now())
        if author != .system {
            undoStack.append(r.entry.seq)
            redoStack.removeAll()
        }
        return r
    }

    /// Undoes the latest Man or accepted-model patch, together with the system patches it caused
    /// (vacancy promotion, auto-commit), by applying their inverses as one system patch.
    public func undo() throws {
        guard let seq = undoStack.last else { return }
        try refuseDuringBreak()
        var group: [LogEntry] = [store.patchLog[seq - 1]]
        for e in store.patchLog.dropFirst(seq) {
            guard e.author == .system, !undoRedoSeqs.contains(e.seq) else { break }
            group.append(e)
        }
        let inverse = group.reversed().flatMap(\.inverse)
        let r = try applyPatch(inverse, author: .system, base: nil, turnID: nil, now: clock.now(), unlimited: true)
        undoStack.removeLast()
        undoRedoSeqs.insert(r.entry.seq)
        redoStack.append(group[0])
        log(.persistence, "undo of patch \(seq) as patch \(r.entry.seq)")
    }

    /// Reapplies the most recently undone patch as system, with the node ids it had (tasks/02).
    public func redo() throws {
        guard let entry = redoStack.last else { return }
        try refuseDuringBreak()
        let r = try applyPatch(Replay.replayable(entry), author: .system, base: nil, turnID: nil,
                               now: clock.now(), unlimited: true)
        redoStack.removeLast()
        undoRedoSeqs.insert(r.entry.seq)
        undoStack.append(r.entry.seq)
        log(.persistence, "redo of patch \(entry.seq) as patch \(r.entry.seq)")
    }

    /// Non-node state the model side owns: held output, proposals, the question, declined memory.
    /// Node changes are not allowed here; they go through `apply` and the patch log (SPEC §3.3).
    public func updateModelState(_ reason: String, _ f: (inout Store) -> Void) {
        var copy = store
        f(&copy)
        precondition(copy.nodes == store.nodes && copy.version == store.version && copy.session == store.session,
                     "updateModelState may not change nodes, the log or the session")
        store = copy
        log(.policy, reason)
        persist()
    }

    public func updateSettings(_ settings: Settings) {
        store.settings = settings
        log(.persistence, "settings changed; session config applies at the next start_session (SPEC §11)")
        persist()
    }

    /// The desk-input sensor (SPEC §6.6.2), when one is installed.
    public func activity(idle: Bool) { send(.activity(idle: idle)) }

    // MARK: Time

    /// Called on wake from sleep. Fires every planned timer that came due, in order, each at its own
    /// instant. Reminders that came due during sleep are announced once, not each (tasks/02).
    public func handleWake() {
        log(.schedule, "wake; \(plannedTimers.count) timer(s) planned")
        fireDue(collapseReminders: true)
    }

    /// Test mode: a 60× timeline that starts now. Turning it off keeps engine time continuous at 1×
    /// until the session ends, so the state and the planned instants do not change; only how far away
    /// they are in real time does (tasks/02).
    public func setTestMode(_ on: Bool, factor: Double = 60) {
        guard on != testMode else { return }
        let now = clock.now()
        if on {
            clock = ScaledClock(factor: factor, base: now, real: realClock)
        } else {
            clock = sessionActive ? ScaledClock(factor: 1, base: now, real: realClock) : realClock
        }
        testMode = on
        log(.schedule, "test mode \(on ? "on (\(Int(factor))×)" : "off")")
        replanTimers()
    }

    // MARK: Internals

    private func reduce(_ event: Event, now: Date) {
        let before = store.session?.state
        let fx = Engine.handle(event, store: &store, now: now)
        logTransition(from: before, cause: "\(event)", at: now)
        perform(fx, now: now)
        persist()
    }

    private func applyPatch(_ ops: [Op], author: Author, base: Int?, turnID: String?, now: Date,
                            unlimited: Bool = false) throws -> ApplyResult {
        let before = store.session?.state
        let saved = store.settings
        if unlimited {
            // Undo and redo restore what limits once allowed; they are not new edits (SPEC §5.4 limits).
            store.settings.maxOpsPerPatch = .max; store.settings.maxNewNodesPerPatch = .max
        }
        defer { if unlimited { store.settings = saved } }
        do {
            let (r, fx) = try Engine.applyPatch(ops, author: author, store: &store, now: now, base: base, turnID: turnID)
            lastUnblocked = r.unblocked
            log(.transition, "patch \(r.entry.seq) by \(author.rawValue): \(ops.count) op(s)" +
                (r.unblocked.isEmpty ? "" : "; unblocked \(r.unblocked.joined(separator: ","))"))
            logTransition(from: before, cause: "patch \(r.entry.seq)", at: now)
            perform(fx, now: now)
            persist()
            for o in patchObservers { o(r) }
            return r
        } catch {
            log(.transition, "patch by \(author.rawValue) refused: \(error)")
            throw error
        }
    }

    private func refuseDuringBreak() throws {
        if store.session?.state == .break { throw ValidationError.patchesBlockedDuringBreak }   // SPEC §6.8
    }

    private func perform(_ effects: [Effect], now: Date) {
        for f in effects {
            log(.effect, Self.describe(f))
            switch f {
            case .announce(let a):
                announce(a, at: now)
            case .schedule(let kind, let at):
                plan(kind, at: at)
            case .cancelTimers:
                cancelAllTimers()
            case .startModelTurn(let deadline):
                // SPEC §13 #11. The engine only emits this on STATUS entry; reaching it elsewhere is a bug.
                precondition(store.session.map { !$0.state.modelSilent } ?? true,
                             "startModelTurn in a silent state")
                coordinator?.startPhaseTurn(deadline: deadline)
            case .renderHeld:
                coordinator?.renderHeld()
            case .expireProposals:
                coordinator?.expireProposals()
            case .sessionEnded:
                coordinator?.sessionEnded()
                store.session = nil                    // SPEC §6.5: end_session → session = null
                if !testMode, clock !== realClock {
                    clock = realClock                  // the offset timeline from test mode is discarded
                    log(.schedule, "engine time back on the real clock")
                }
            }
        }
    }

    private func announce(_ a: Announcement, at: Date) {
        nextAnnouncementID += 1
        let t = TimedAnnouncement(id: nextAnnouncementID, at: at, announcement: a, state: store.session?.state)
        announcements.append(t)
        if announcements.count > Self.announcementLimit { announcements.removeFirst(announcements.count - Self.announcementLimit) }
        lastAnnouncement = t
        log(.announcement, a.text)
        for o in announcementObservers { o(t) }
    }

    private func plan(_ kind: TimerKind, at: Date) {
        timerTokens[kind]?.cancel()
        planCounter += 1
        plannedOrder[kind] = planCounter
        plannedTimers[kind] = at
        schedule(kind, at: at)
    }

    private func schedule(_ kind: TimerKind, at: Date) {
        let gen = generation
        timerTokens[kind] = clock.schedule(at: at) { [weak self] in
            // A tick from a cancelled generation never reaches the engine (tasks/02).
            guard let self, gen == self.generation else { return }
            // A timer that fired is due at its own instant, even if a scaled clock's arithmetic reads a hair earlier.
            self.fireDue(collapseReminders: false, atLeast: at)
        }
    }

    private func cancelAllTimers() {
        generation += 1
        for t in timerTokens.values { t.cancel() }
        timerTokens.removeAll()
        plannedTimers.removeAll()
        plannedOrder.removeAll()
    }

    private func replanTimers() {
        generation += 1
        for t in timerTokens.values { t.cancel() }
        timerTokens.removeAll()
        for (kind, at) in plannedTimers { schedule(kind, at: at) }
        fireDue(collapseReminders: false)
    }

    /// Fires due timers earliest first (ties in the order they were planned), as `Simulator.advance` does.
    private func fireDue(collapseReminders: Bool, atLeast floor: Date = .distantPast) {
        while true {
            let now = max(clock.now(), floor)
            let due = plannedTimers.filter { $0.value <= now }
                .sorted { ($0.value, plannedOrder[$0.key] ?? 0) < ($1.value, plannedOrder[$1.key] ?? 0) }
            guard let (kind, at) = due.first else { return }
            unplan(kind)
            if collapseReminders, case .reminder = kind,
               due.dropFirst().contains(where: { if case .reminder = $0.key { return true } else { return false } }) {
                log(.schedule, "reminder \(kind) missed during sleep; folded into a later one")
                continue
            }
            reduce(.tick(kind), now: at)
        }
    }

    private func unplan(_ kind: TimerKind) {
        timerTokens[kind]?.cancel()
        timerTokens[kind] = nil
        plannedTimers[kind] = nil
        plannedOrder[kind] = nil
    }

    private func persist() { persistence?.record(store) }

    private func logTransition(from before: SessionState?, cause: String, at: Date) {
        let after = store.session?.state
        guard before != after else { return }
        log(.transition, "\(before?.rawValue ?? "none") → \(after?.rawValue ?? "none") on \(cause)", at: at)
    }

    public func log(_ kind: SystemLogRecord.Kind, _ message: String, at: Date? = nil) {
        let r = SystemLogRecord(at: at ?? clock.now(), kind: kind, message: message)
        recentSystemLog.append(r)
        if recentSystemLog.count > Self.systemLogLimit { recentSystemLog.removeFirst(recentSystemLog.count - Self.systemLogLimit) }
        persistence?.appendSystem(r)
    }

    static func describe(_ f: Effect) -> String {
        switch f {
        case .announce(let a): return "announce: \(a.text)"
        case .schedule(let k, let at): return "schedule \(k) at \(at.timeIntervalSince1970)"
        case .cancelTimers: return "cancel timers"
        case .startModelTurn(let d): return "start model turn, deadline \(d.timeIntervalSince1970)"
        case .renderHeld: return "render held"
        case .expireProposals: return "expire proposals"
        case .sessionEnded: return "session ended"
        }
    }
}
