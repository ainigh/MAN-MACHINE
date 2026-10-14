import XCTest
import MpmCore
@testable import MpmHost

@MainActor
final class MonitorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mpm-monitor-\(UUID().uuidString)")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    struct Rig {
        let clock: ManualClock
        let controller: SessionController
        let coordinator: ModelTurnCoordinator
        let persistence: Persistence
        let ids: [String: NodeID]
        @MainActor var monitor: Monitor { controller.monitor }
    }

    func rig(_ adapter: ModelAdapter = NullAdapter()) throws -> Rig {
        var settings = Settings.default
        settings.session = SessionConfig(R: 360, r: 3, Ls: 900, Lb: 120)
        var store = Store(rootTitle: "GOAL", now: t0, settings: settings, rootID: "root")
        var ids: [String: NodeID] = [:]
        for (i, name) in ["n1", "n2", "n3"].enumerated() {
            ids[name] = try store.apply([.add(name, under: "root", tmp: name)], author: .man,
                                        now: t0.addingTimeInterval(Double(i))).entry.assignedIDs[name]!
        }
        let p = Persistence(directory: dir, debounce: 0)
        _ = try p.load(now: t0)
        let clock = ManualClock(t0.addingTimeInterval(10))
        let coord = ModelTurnCoordinator(adapter: adapter)
        let c = SessionController(store: store, clock: clock, persistence: p, coordinator: coord)
        coord.controller = c
        return Rig(clock: clock, controller: c, coordinator: coord, persistence: p, ids: ids)
    }

    /// Every hand-off the host reports must be an edge the panel can draw.
    func assertEdgesDrawn(_ m: Monitor, file: StaticString = #filePath, line: UInt = #line) {
        for e in m.events {
            guard let to = e.to else { continue }
            XCTAssertNotNil(MonitorLayout.edge(e.from, to), "\(e.from) → \(to): \(e.title)", file: file, line: line)
        }
    }

    func runRoundToStatus(_ r: Rig) {
        r.controller.send(.startSession)
        r.controller.send(.commit(doing: r.ids["n1"]!, next: r.ids["n2"]!))
        r.clock.advance(by: 200)                                        // past the first reminder (3:00 left)
        try! r.controller.apply([.setStatus(r.ids["n1"]!, .done)])
        r.controller.send(.finish)
    }

    /// Lets the persistence queue's reports hop back to the main actor.
    func settle(_ r: Rig) async {
        r.persistence.flush()
        for _ in 0..<20 { await Task.yield() }
    }

    func testARoundShowsEventsTicksEffectsAndTransitions() async throws {
        let r = try rig()
        runRoundToStatus(r)
        let m = r.monitor
        XCTAssertEqual(r.controller.state, .status)

        let fromMan = m.events.filter { $0.from == .man && $0.to == .engine }.map(\.title)
        XCTAssertEqual(fromMan, ["start_session", "commit", "finish"])
        XCTAssertTrue(m.events.contains { $0.from == .timers && $0.to == .engine && $0.title.hasPrefix("tick reminder") })
        XCTAssertTrue(m.events.contains { $0.from == .engine && $0.to == .timers && $0.title == "schedule round end" })
        XCTAssertTrue(m.events.contains { $0.from == .engine && $0.to == .output && $0.title == Announcement.sessionOpen.text })
        XCTAssertTrue(m.events.contains { $0.from == .engine && $0.to == .coordinator && $0.title == "phase turn" })
        XCTAssertTrue(m.events.contains { $0.from == .man && $0.to == .store && $0.outcome == .ok })
        let transitions = m.events.filter { $0.from == .engine && $0.to == nil }.map(\.title)
        XCTAssertEqual(transitions, ["none → idle", "idle → work", "work → status"])
        // No model configured: the coordinator says so, quietly.
        XCTAssertTrue(m.events.contains { $0.from == .coordinator && $0.title == "phase turn not started" })
        XCTAssertNil(m.worstUnseen)
        assertEdgesDrawn(m)
    }

    func testARefusedPatchIsAnUnseenErrorOnTheStoreUntilAcknowledged() async throws {
        let r = try rig()
        XCTAssertThrowsError(try r.controller.apply([.setStatus("nope", .done)]))
        let m = r.monitor
        let e = try XCTUnwrap(m.events.last)
        XCTAssertEqual(e.outcome, .error)
        XCTAssertEqual(e.from, .man)
        XCTAssertEqual(e.to, .store)
        XCTAssertFalse(e.detail.isEmpty)
        XCTAssertEqual(m.unseen[.store], .error)
        XCTAssertEqual(m.unseenTotal, 1)
        XCTAssertEqual(m.lastOutcome(.store), .error)
        m.acknowledge(.store)
        XCTAssertNil(m.worstUnseen)
        XCTAssertEqual(m.lastOutcome(.store), .error)                   // history stays; only the badge clears
    }

    func testARefusedEngineEventIsAWarning() async throws {
        let r = try rig()
        r.controller.send(.finish)                                      // no session
        XCTAssertEqual(r.monitor.events.last?.title, Announcement.notAvailable.text)
        XCTAssertEqual(r.monitor.unseen[.engine], .warning)
    }

    func testAModelThatNeverAnswersShowsWorkThenAMissedDeadlineThenAFailure() async throws {
        let r = try rig(FakeAdapter(.never))
        runRoundToStatus(r)
        let m = r.monitor
        XCTAssertEqual(m.activity[.model]?.label, "phase")
        XCTAssertNotNil(m.activity[.model]?.deadline)
        r.clock.advance(to: r.controller.store.session!.phaseEnd!)
        XCTAssertTrue(m.events.contains { $0.from == .model && $0.outcome == .warning && $0.title == "deadline missed" })
        r.clock.advance(by: ModelTurnCoordinator.lateLimit + 60)
        await r.coordinator.waitUntilIdle()
        XCTAssertNil(m.activity[.model])
        XCTAssertTrue(m.events.contains { $0.to == .model && $0.title == "turn abandoned" })
        let closed = try XCTUnwrap(m.events.last { $0.from == .model && $0.to == .coordinator })
        XCTAssertEqual(closed.outcome, .error)
        XCTAssertTrue(closed.detail.contains("deadline met: no"), closed.detail)
        XCTAssertNotNil(closed.turnID)
        XCTAssertEqual(m.unseen[.coordinator], .error)
        assertEdgesDrawn(m)
    }

    func testAnAnswerInTimeIsOkWithTheRawOutputInItsDetail() async throws {
        let fake = FakeAdapter(.immediate("```envelope\n{\"say\":\"Good round.\",\"ask\":null,\"patch\":[],\"next\":null}\n```"))
        let r = try rig(fake)
        runRoundToStatus(r)
        await r.coordinator.waitUntilIdle()
        let m = r.monitor
        let closed = try XCTUnwrap(m.events.last { $0.from == .model && $0.to == .coordinator })
        XCTAssertEqual(closed.outcome, .ok)
        XCTAssertTrue(closed.detail.contains("raw output:"), closed.detail)
        XCTAssertTrue(closed.detail.contains("prompt:"), closed.detail)
        XCTAssertTrue(m.events.contains { $0.from == .coordinator && $0.to == .store && $0.title == "held until STRATEGY" })
        r.clock.advance(to: r.controller.store.session!.phaseEnd!)
        XCTAssertTrue(m.events.contains { $0.from == .coordinator && $0.to == .output && $0.detail.contains("Good round.") })
        XCTAssertNil(m.worstUnseen)
        assertEdgesDrawn(m)
    }

    func testDiskWritesAreReportedAndEndTheWritingActivity() async throws {
        let r = try rig()
        r.controller.send(.startSession)
        XCTAssertEqual(r.monitor.activity[.disk]?.label, "writing")
        await settle(r)
        XCTAssertNil(r.monitor.activity[.disk])
        XCTAssertTrue(r.monitor.events.contains { $0.from == .store && $0.to == .disk && $0.title.hasPrefix("snapshot written") })
    }

    func testADiskFailureIsAnUnseenError() async throws {
        let r = try rig()
        try FileManager.default.removeItem(at: dir)
        try Data().write(to: dir)                                       // a file where the folder was: every write fails
        r.controller.send(.startSession)
        await settle(r)
        XCTAssertEqual(r.monitor.unseen[.disk], .error)
        XCTAssertTrue(r.monitor.events.contains { $0.to == .disk && $0.outcome == .error && $0.detail.contains("failed") })
        XCTAssertNil(r.monitor.activity[.disk])
    }

    // MARK: Pure parts

    func testInFlightUsesRealTimeAndSkipsEventsWithoutAnEdge() async {
        var now = t0
        let m = Monitor(realNow: { now })
        m.emit(.man, to: .engine, .info, "a", at: t0)
        now += 0.2
        m.emit(.engine, .info, "work inside", at: t0)
        m.emit(.engine, to: .timers, .info, "b", at: t0)
        let flying = m.inFlight(now: t0.addingTimeInterval(0.3), duration: 0.5)
        XCTAssertEqual(flying.map(\.event.title), ["a", "b"])
        XCTAssertEqual(flying[0].progress, 0.6, accuracy: 1e-6)
        XCTAssertTrue(m.inFlight(now: t0.addingTimeInterval(2), duration: 0.5).isEmpty)
    }

    func testTheEventListIsBounded() async {
        let m = Monitor()
        for i in 0..<(Monitor.limit + 10) { m.emit(.engine, .info, "\(i)", at: t0) }
        XCTAssertEqual(m.events.count, Monitor.limit)
        XCTAssertEqual(m.events.first?.title, "10")
    }

    func testEveryComponentHasAPlaceAndEveryEdgeJoinsPlacedComponents() async {
        for c in Component.allCases { XCTAssertNotNil(MonitorLayout.position[c], "\(c)") }
        for e in MonitorLayout.edges { XCTAssertNotEqual(e.a, e.b) }
        XCTAssertEqual(Set(MonitorLayout.edges).count, MonitorLayout.edges.count)
    }
}
