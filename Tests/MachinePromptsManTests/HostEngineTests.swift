import XCTest
import MpmCore
@testable import MpmHost

/// Same script, two drivers: the core `Simulator` (the reference) and the host controller on a scaled clock.
@MainActor
protocol SessionDriver: AnyObject {
    var store: Store { get }
    var engineNow: Date { get }
    func send(_ e: Event)
    @discardableResult func patch(_ ops: [Op]) throws -> ApplyResult
    func advance(_ seconds: TimeInterval)
    func advance(until state: SessionState)
    var texts: [String] { get }
}

@MainActor
final class SimulatorDriver: SessionDriver {
    var sim: Simulator
    init(store: Store, now: Date) { sim = Simulator(store: store, now: now) }
    var store: Store { sim.store }
    var engineNow: Date { sim.now }
    func send(_ e: Event) { sim.send(e) }
    func patch(_ ops: [Op]) throws -> ApplyResult { try sim.patch(ops) }
    func advance(_ seconds: TimeInterval) { sim.advance(seconds) }
    func advance(until state: SessionState) { sim.advance(until: state) }
    var texts: [String] { sim.announcements.map(\.1.text) }
}

@MainActor
final class ControllerDriver: SessionDriver {
    let real: ManualClock
    let controller: SessionController
    let base: Date
    let realBase: Date
    let factor: Double
    var target: Date
    var collected: [String] = []

    init(store: Store, now: Date, factor: Double = 600) {
        real = ManualClock(now)       // test mode starts its scaled timeline at the real clock's now
        realBase = real.now()
        base = now
        target = now
        self.factor = factor
        controller = SessionController(store: store, clock: real)
        controller.setTestMode(true, factor: factor)
        controller.announcementObservers.append { [unowned self] a in self.collected.append(a.text) }
    }
    var store: Store { controller.store }
    var engineNow: Date { controller.now() }
    func send(_ e: Event) { controller.send(e) }
    func patch(_ ops: [Op]) throws -> ApplyResult { try controller.apply(ops) }
    func advance(_ seconds: TimeInterval) { move(to: target.addingTimeInterval(seconds)) }
    func advance(until state: SessionState) {
        var guardCount = 0
        while controller.store.session?.state != state, let next = controller.plannedTimers.values.min(), guardCount < 1000 {
            move(to: next); guardCount += 1
        }
    }
    private func move(to engine: Date) {
        target = engine
        real.advance(to: realBase.addingTimeInterval(engine.timeIntervalSince(base) / factor))
    }
    var texts: [String] { collected }
}

@MainActor
final class HostEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func starting(config: SessionConfig = SessionConfig(R: 360, r: 3, Ls: 900, Lb: 120)) -> (Store, [String: NodeID]) {
        var settings = Settings.default
        settings.session = config
        var store = Store(rootTitle: "GOAL", now: t0, settings: settings, rootID: "root")
        var ids: [String: NodeID] = [:]
        for (i, name) in ["n1", "n2", "n3", "n4"].enumerated() {
            let r = try! store.apply([.add(name, under: "root", tmp: name)], author: .man, now: t0.addingTimeInterval(Double(i)))
            ids[name] = r.entry.assignedIDs[name]!
        }
        return (store, ids)
    }

    /// The script of `IllustratedSessionTests.testFullSession`, driver-agnostic.
    func illustrated(_ d: SessionDriver, _ startIDs: [String: NodeID]) throws {
        var id = startIDs
        func mm(_ m: Int, _ s: Int = 0) -> TimeInterval { Double(m * 60 + s) }
        d.send(.startSession)
        d.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        d.advance(mm(2, 10))
        id["n5"] = try d.patch([.add("n5", under: "root", tmp: "n5")]).entry.assignedIDs["n5"]
        d.advance(mm(0, 50))
        d.advance(mm(1, 20))
        try d.patch([.setStatus(id["n1"]!, .done), .setStatus(id["n3"]!, .done)])
        d.send(.finish)
        d.advance(until: .strategy)
        d.advance(mm(0, 20))
        d.send(.commit(doing: id["n2"]!, next: id["n4"]!))
        d.advance(mm(3, 50))
        try d.patch([.crossOut(id: id["n2"]!), .setStatus(id["n4"]!, .doing), .setStatus(id["n5"]!, .next)])
        d.advance(until: .timeUp)
        d.send(.snooze)
        d.advance(mm(0, 30))
        try d.patch([.setStatus(id["n4"]!, .done)])
        d.send(.finish)
        d.advance(until: .strategy)
        id["n6"] = try d.patch([.add("n6", under: "root", tmp: "n6")]).entry.assignedIDs["n6"]
        d.advance(mm(0, 45) - 1)
        d.send(.commit(doing: id["n5"]!, next: id["n6"]!))
        d.advance(until: .work)
        for _ in 1...3 { d.advance(until: .timeUp); d.send(.snooze) }
        d.advance(until: .timeUp)
        d.send(.snooze)
        let r78 = try d.patch([.add("n7", under: id["n5"]!, tmp: "n7"), .add("n8", under: id["n5"]!, tmp: "n8")])
        id["n7"] = r78.entry.assignedIDs["n7"]; id["n8"] = r78.entry.assignedIDs["n8"]
        d.advance(until: .strategy)
        d.advance(mm(0, 45) - 1)
        d.send(.commit(doing: id["n7"]!, next: id["n8"]!))
        d.send(.commit(doing: id["n8"]!, next: id["n7"]!))
        d.send(.endSession)
    }

    // MARK: Acceptance

    func testIllustratedSessionMatchesTheSimulatorAt600x() async throws {
        let (store, id) = starting()
        let reference = SimulatorDriver(store: store, now: t0.addingTimeInterval(60))
        try illustrated(reference, id)
        let host = ControllerDriver(store: store, now: t0.addingTimeInterval(60), factor: 600)
        try illustrated(host, id)

        XCTAssertGreaterThan(reference.texts.count, 30)
        XCTAssertEqual(host.texts, reference.texts)
        XCTAssertTrue(host.texts.contains("No snoozes left. Stop."))
        XCTAssertTrue(host.texts.contains("Seated 13:54. Movement break, 2 min."))
        XCTAssertNil(host.controller.store.session)                  // SPEC §6.5: end_session → null
        XCTAssertTrue(host.controller.plannedTimers.isEmpty)
        func byTitle(_ s: Store) -> [String: Status] { Dictionary(uniqueKeysWithValues: s.nodes.values.map { ($0.title, $0.status) }) }
        XCTAssertEqual(byTitle(host.store), byTitle(reference.store))
    }

    func testCancelledTimerNeverReachesTheEngine() async throws {
        let (store, id) = starting()
        let clock = ManualClock(t0)
        let c = SessionController(store: store, clock: clock)
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        let roundEnd = try XCTUnwrap(c.plannedTimers[.roundEnd])
        clock.advance(to: roundEnd.addingTimeInterval(-0.001))
        c.send(.finish)                                    // cancels every timer 1 ms before round end
        clock.advance(to: roundEnd.addingTimeInterval(1))
        XCTAssertEqual(c.state, .status)
        XCTAssertFalse(c.announcements.contains { $0.text == "Time's up." })
    }

    func testTickFromAStaleGenerationIsDroppedEvenIfTheUnderlyingTimerFires() async throws {
        // A clock whose cancel cannot stop a callback already on its way, as with a dispatch race.
        let (store, id) = starting()
        let clock = LeakyClock(t0)
        let c = SessionController(store: store, clock: clock)
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        clock.now_ = c.plannedTimers[.roundEnd]!.addingTimeInterval(-0.001)
        c.send(.finish)
        clock.now_ = clock.now_.addingTimeInterval(50)     // past round end, before status end (90 s)
        clock.fireEverything()                             // the old roundEnd and reminder callbacks arrive anyway
        XCTAssertFalse(c.announcements.contains { $0.text == "Time's up." })
        XCTAssertEqual(c.state, .status)
    }

    func testTurningTestModeOffMidRoundReplansFromRealTime() async throws {
        let (store, id) = starting()
        let real = ManualClock(t0)
        let c = SessionController(store: store, clock: real)
        c.setTestMode(true)
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        real.advance(by: 2)                                // 120 s of engine time at 60×
        XCTAssertEqual(c.remainingInPhase, 240, accuracy: 1e-6)
        let planned = c.plannedTimers
        let session = c.store.session

        c.setTestMode(false)
        XCTAssertEqual(c.state, .work)
        XCTAssertEqual(c.plannedTimers, planned)
        XCTAssertEqual(c.store.session, session)
        XCTAssertEqual(c.remainingInPhase, 240, accuracy: 1e-6)

        real.advance(by: 239)
        XCTAssertEqual(c.state, .work)
        real.advance(by: 2)
        XCTAssertEqual(c.state, .timeUp)
    }

    // MARK: More host behaviour

    func testWakeFiresDueTimersInOrderAndAnnouncesMissedRemindersOnce() async throws {
        let (store, id) = starting()
        let clock = ManualClock(t0)
        let c = SessionController(store: store, clock: clock)
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        let start = clock.now()
        clock.jump(to: start.addingTimeInterval(330))       // slept through all three reminders
        c.handleWake()
        XCTAssertEqual(c.announcements.filter { $0.text.hasSuffix("left.") }.map(\.text), ["1 min left."])
        XCTAssertEqual(c.state, .work)

        clock.jump(to: start.addingTimeInterval(400))       // through round end and the grace window
        c.handleWake()
        XCTAssertEqual(c.state, .status)
        XCTAssertEqual(Array(c.announcements.map(\.text).suffix(3).prefix(2)), ["Time's up.", "Stop."])
    }

    func testUndoRedoThroughThePatchLogKeepsIds() async throws {
        let (store, _) = starting()
        let c = SessionController(store: store, clock: ManualClock(t0))
        let r = try c.apply([.add("typo", under: "root", tmp: "x")])
        let newID = r.entry.assignedIDs["x"]!
        try c.undo()
        XCTAssertNil(c.store.nodes[newID])
        try c.redo()
        XCTAssertEqual(c.store.nodes[newID]?.title, "typo")
        XCTAssertEqual(c.store.version, c.store.patchLog.count)
        XCTAssertFalse(c.canRedo)
    }

    func testUndoTakesTheSystemFollowUpsWithIt() async throws {
        let (store, id) = starting()
        let c = SessionController(store: store, clock: ManualClock(t0))
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        try c.apply([.setStatus(id["n1"]!, .done)])        // promotes n2 by a system patch
        XCTAssertEqual(c.store.doing?.id, id["n2"])
        try c.undo()
        XCTAssertEqual(c.store.doing?.id, id["n1"])
        XCTAssertEqual(c.store.next?.id, id["n2"])
    }

    func testAnnouncementsAreBounded() async throws {
        let (store, _) = starting()
        let c = SessionController(store: store, clock: ManualClock(t0))
        for _ in 0..<80 { c.send(.finish) }                // "Not available now." each time
        XCTAssertEqual(c.announcements.count, SessionController.announcementLimit)
        XCTAssertEqual(c.lastAnnouncement?.text, "Not available now.")
    }

    func testCoordinatorGetsEffectsInOrderAndModelIsSilentDuringWork() async throws {
        let (store, id) = starting()
        let clock = ManualClock(t0)
        let rec = RecordingCoordinator()
        let c = SessionController(store: store, clock: clock, coordinator: rec)
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        clock.advance(by: 100)
        XCTAssertTrue(rec.calls.isEmpty)                   // nothing during WORK (SPEC §13 #11)
        c.send(.finish)
        let deadline = try XCTUnwrap(c.store.session?.phaseEnd)
        XCTAssertEqual(rec.calls, [.startPhaseTurn(deadline)])
        clock.advance(to: deadline)
        XCTAssertEqual(rec.calls.last, .renderHeld)
        c.send(.commit(doing: id["n2"]!, next: id["n3"]!))
        XCTAssertEqual(rec.calls.last, .expireProposals)
        c.send(.endSession)
        XCTAssertEqual(rec.calls.last, .sessionEnded)
    }

    func testEveryEffectAndTransitionIsInTheSystemLog() async throws {
        let (store, id) = starting()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mpm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = Persistence(directory: dir)
        _ = try p.load(now: t0)
        let c = SessionController(store: store, clock: ManualClock(t0), persistence: p)
        c.send(.startSession)
        c.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        p.flush()
        let lines = JSONLines.read(SystemLogRecord.self, from: p.systemLogURL).values
        XCTAssertTrue(lines.contains { $0.kind == .transition && $0.message.hasPrefix("idle → work") })
        XCTAssertTrue(lines.contains { $0.kind == .effect && $0.message.hasPrefix("schedule roundEnd") })
        XCTAssertTrue(lines.contains { $0.kind == .announcement && $0.message == "Session open. Commit to start." })
    }
}

/// Fires callbacks regardless of cancellation, to prove the controller's generation guard.
@MainActor
final class LeakyClock: Clock {
    var now_: Date
    var callbacks: [(at: Date, f: @MainActor @Sendable () -> Void)] = []
    init(_ d: Date) { now_ = d }
    func now() -> Date { now_ }
    func schedule(at date: Date, _ f: @escaping @MainActor @Sendable () -> Void) -> Cancellable {
        callbacks.append((date, f)); return Noop()
    }
    /// Fires every callback that is due, cancelled or not.
    func fireEverything() {
        let due = callbacks.filter { $0.at <= now_ }
        callbacks.removeAll { $0.at <= now_ }
        for c in due { c.f() }
    }
    final class Noop: Cancellable { func cancel() {} }
}
