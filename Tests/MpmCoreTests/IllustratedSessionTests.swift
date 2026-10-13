import XCTest
@testable import MpmCore

/// Replays "Protocol — Illustrated Session" (R 6 min, r 3, Ls 15 min, Lb 2 min) and checks every number in it.
final class IllustratedSessionTests: XCTestCase {

    func testFullSession() throws {
        var (store, id) = Fixtures.starting()
        var sim = Simulator(store: store, now: Fixtures.t0.addingTimeInterval(60))
        let start = sim.now
        func clock() -> TimeInterval { sim.now.timeIntervalSince(start) }
        func mm(_ m: Int, _ s: Int = 0) -> TimeInterval { Double(m * 60 + s) }

        sim.send(.startSession)
        XCTAssertEqual(sim.state, .idle)

        // ---- Round 1: in the zone ----
        sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        XCTAssertEqual(sim.state, .work)
        XCTAssertEqual(sim.store.doing?.id, id["n1"]); XCTAssertEqual(sim.store.next?.id, id["n2"])

        sim.advance(mm(2, 10))
        let r = try sim.patch([.add("n5", under: "root", tmp: "n5")]); id["n5"] = r.entry.assignedIDs["n5"]
        sim.advance(mm(0, 50))                                     // 3:00
        XCTAssertEqual(sim.announcements.last?.1, .reminder(remaining: 180))

        sim.advance(mm(1, 20))                                     // 4:20
        try sim.patch([.setStatus(id["n1"]!, .done), .setStatus(id["n3"]!, .done)])
        // D vacant → N promoted (SPEC §6.7)
        XCTAssertEqual(sim.store.doing?.id, id["n2"])
        XCTAssertEqual(sim.announcements.last?.1, .nowDoing("n2"))
        sim.send(.finish)
        XCTAssertEqual(sim.state, .status)
        XCTAssertEqual(sim.store.session?.x, 2)
        XCTAssertEqual(sim.store.session?.statusLength, 30)         // 45·2/3
        XCTAssertEqual(clock(), mm(4, 20))

        sim.advance(until: .strategy)
        XCTAssertEqual(clock(), mm(4, 50))
        sim.advance(mm(0, 20))                                     // 5:10, strategy ended early by commit
        sim.send(.commit(doing: id["n2"]!, next: id["n4"]!))
        XCTAssertEqual(sim.state, .work)
        XCTAssertEqual(sim.store.session?.round, 2)
        // "Seated 5:10 … Continue."
        XCTAssertTrue(sim.announcements.contains { if case .continue(let s) = $0.1 { return s == mm(5, 10) } else { return false } })

        // ---- Round 2: a dead end and a snooze ----
        sim.advance(mm(3, 50))                                     // 9:00
        try sim.patch([.crossOut(id: id["n2"]!), .setStatus(id["n4"]!, .doing), .setStatus(id["n5"]!, .next)])
        XCTAssertEqual(sim.store.nodes[id["n2"]!]?.status, .crossedOut)
        XCTAssertEqual(sim.store.doing?.id, id["n4"])

        sim.advance(until: .timeUp)
        XCTAssertEqual(clock(), mm(11, 10))
        // reminders 2 and 3 fired at 1:30 and 1:00 (clamped from 0:45)
        let rems = sim.announcements.compactMap { if case .reminder(let t) = $0.1 { return t } else { return nil } }
        XCTAssertEqual(rems, [180, 180, 90, 60])
        sim.send(.snooze)
        XCTAssertEqual(sim.state, .snooze); XCTAssertEqual(sim.store.session?.z, 1)

        sim.advance(mm(0, 30))                                     // 11:40
        try sim.patch([.setStatus(id["n4"]!, .done)])
        XCTAssertEqual(sim.store.doing?.id, id["n5"])              // promoted again
        sim.send(.finish)
        XCTAssertEqual(sim.store.session?.x, 1)
        XCTAssertEqual(sim.store.session?.statusLength, 90)        // 45·4/2

        sim.advance(until: .strategy)
        XCTAssertEqual(clock(), mm(13, 10))
        let r6 = try sim.patch([.add("n6", under: "root", tmp: "n6")]); id["n6"] = r6.entry.assignedIDs["n6"]
        sim.advance(mm(0, 45) - 1)                                 // 13:54: B uses nearly all of strategy
        sim.send(.commit(doing: id["n5"]!, next: id["n6"]!))
        XCTAssertEqual(sim.state, .break)                          // 13:54 + 6 > 15
        XCTAssertEqual(sim.store.doing?.id, id["n5"]); XCTAssertEqual(sim.store.next?.id, id["n6"])

        XCTAssertTrue(sim.announcements.contains { if case .movementBreak(let s, let lb) = $0.1 { return s == mm(13, 54) && lb == 120 } else { return false } })

        sim.advance(until: .work)
        XCTAssertEqual(clock(), mm(15, 54))
        XCTAssertEqual(sim.store.session?.round, 3)
        XCTAssertEqual(sim.store.session!.seated(at: sim.now), 0)

        // ---- Round 3: stuck, pushing through ----
        for z in 1...3 {
            sim.advance(until: .timeUp)
            sim.send(.snooze)
            XCTAssertEqual(sim.store.session?.z, z)
        }
        sim.advance(until: .timeUp)
        XCTAssertEqual(clock(), mm(24, 9))
        sim.send(.snooze)                                          // "One more." → refused
        XCTAssertEqual(sim.state, .status)
        XCTAssertTrue(sim.announcements.contains { $0.1 == .noSnoozesLeft })
        XCTAssertEqual(sim.store.session?.x, 0)
        XCTAssertEqual(sim.store.session?.statusLength, 720)       // 45·16/1 = 12 min

        let r78 = try sim.patch([.add("n7", under: id["n5"]!, tmp: "n7"), .add("n8", under: id["n5"]!, tmp: "n8")])
        id["n7"] = r78.entry.assignedIDs["n7"]; id["n8"] = r78.entry.assignedIDs["n8"]

        sim.advance(until: .strategy)
        XCTAssertEqual(clock(), mm(36, 9))
        XCTAssertEqual(sim.store.session!.seated(at: sim.now), 0)   // long status phase reset it
        sim.advance(mm(0, 45) - 1)
        sim.send(.commit(doing: id["n7"]!, next: id["n8"]!))
        XCTAssertEqual(sim.state, .work)
        XCTAssertEqual(sim.store.nodes[id["n5"]!]?.status, .open)   // displaced from doing
        XCTAssertTrue(sim.announcements.contains { if case .continue(let s) = $0.1 { return abs(s - 44) < 0.01 } else { return false } })

        // Snooze in STATUS is "too late"; commit in WORK is not available.
        sim.send(.commit(doing: id["n8"]!, next: id["n7"]!))
        XCTAssertEqual(sim.announcements.last?.1, .notAvailable)

        sim.send(.endSession)
        XCTAssertEqual(sim.state, .end)
        XCTAssertTrue(sim.timers.isEmpty)

        // Nodes are never deleted; the whole history is in the log.
        XCTAssertEqual(sim.store.nodes.count, 9)
        XCTAssertEqual(sim.store.version, sim.store.patchLog.count)
    }

    func testAutoCommitKeepsDoingPromotesNextFillsFromOldestOpen() throws {
        let (store, id) = Fixtures.starting()
        var sim = Simulator(store: store, now: Fixtures.t0)
        sim.send(.startSession); sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        // Case 1: D unfinished, N set, no choice → keep both.
        sim.advance(until: .timeUp); sim.send(.stop); sim.advance(until: .strategy); sim.advance(until: .work)
        XCTAssertEqual(sim.store.doing?.id, id["n1"]); XCTAssertEqual(sim.store.next?.id, id["n2"])
        XCTAssertEqual(sim.store.session?.round, 2)
        // Case 2: D done mid-round → N promoted, N vacant; no choice → N = oldest open (n3).
        try sim.patch([.setStatus(id["n1"]!, .done)])
        sim.send(.finish); sim.advance(until: .strategy); sim.advance(until: .work)
        XCTAssertEqual(sim.store.doing?.id, id["n2"]); XCTAssertEqual(sim.store.next?.id, id["n3"])
        XCTAssertTrue(sim.announcements.contains { if case .autoCommit = $0.1 { return true } else { return false } })
        // Case 3: nothing open at all → IDLE.
        try sim.patch([.setStatus(id["n2"]!, .done), .setStatus(id["n3"]!, .done), .setStatus(id["n4"]!, .done)])
        sim.send(.finish); sim.advance(until: .strategy); sim.advance(until: .idle)
        XCTAssertEqual(sim.state, .idle)
        XCTAssertTrue(sim.announcements.contains { $0.1 == .noOpenNodes })
    }

    func testGraceTimeoutIsStop() {
        let (store, id) = Fixtures.starting()
        var sim = Simulator(store: store, now: Fixtures.t0)
        sim.send(.startSession); sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        sim.advance(until: .timeUp)
        sim.advance(10)
        XCTAssertEqual(sim.state, .status)
        XCTAssertTrue(sim.announcements.contains { $0.1 == .stop })
        XCTAssertEqual(sim.store.session?.statusLength, 90)   // z 0, x 0 → 2q
    }

    func testCommitByPatchStartsRound() throws {
        let (store, id) = Fixtures.starting()
        var sim = Simulator(store: store, now: Fixtures.t0)
        sim.send(.startSession)
        try sim.patch([.setStatus(id["n1"]!, .doing), .setStatus(id["n2"]!, .next)])
        XCTAssertEqual(sim.state, .work)
    }

    func testBreakBlocksPatches() {
        var (store, id) = Fixtures.starting(config: SessionConfig(R: 360, r: 3, Ls: 400, Lb: 120))
        var sim = Simulator(store: store, now: Fixtures.t0)
        sim.send(.startSession); sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        sim.advance(until: .timeUp); sim.send(.stop)
        sim.advance(until: .strategy); sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        XCTAssertEqual(sim.state, .break)
        XCTAssertThrowsError(try sim.patch([.setStatus(id["n3"]!, .done)]))
        store = sim.store; _ = store
    }

    func testTranscriptReadsLikeTheProtocolDoc() {
        let (store, id) = Fixtures.starting()
        var sim = Simulator(store: store, now: Fixtures.t0)
        sim.send(.startSession); sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        sim.advance(until: .timeUp)
        let t = sim.transcript()
        XCTAssertTrue(t.contains("Round 1. n1 doing, n2 next. 6 min, starting now."))
        XCTAssertTrue(t.contains("3 min left."))
        XCTAssertTrue(t.contains("1 min left."))
        XCTAssertTrue(t.hasSuffix("Time's up."))
    }
}
