import XCTest
import MpmCore
@testable import MpmHost

/// Bugs found while building the monitor panel, each pinned by the scenario that showed it.
extension ModelTurnTests {

    func testAcceptingPartOfAProposalLeavesTheRestAcceptable() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        let n3 = r.ids["n3"]!
        let p = Proposal(id: "p1", turnID: "t1", at: r.clock.now(),
                         ops: [.updateNode(id: n3, fields: NodeFields(title: "n3 renamed")),
                               .updateNode(id: n3, fields: NodeFields(progress: 50))], say: "")
        r.controller.updateModelState("test") { $0.pending = [p] }
        r.clock.advance(by: 5)
        try r.coordinator.accept("p1", ops: [0])
        let rest = try XCTUnwrap(r.controller.store.pending.first)
        XCTAssertFalse(r.coordinator.isStale(rest), "the proposal's own accepted op is not a change to it")
        try r.coordinator.accept("p1")
        XCTAssertEqual(r.controller.store.nodes[n3]?.progress, 50)
        XCTAssertTrue(r.controller.store.pending.isEmpty)
    }

    func testOpsLeftAfterAcceptingAnAddReferToTheNewNode() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        let p = Proposal(id: "p1", turnID: "t1", at: r.clock.now(),
                         ops: [.add("child", under: "root", tmp: "a"),
                               .updateNode(id: Op.tmp("a"), fields: NodeFields(progress: 20))], say: "")
        r.controller.updateModelState("test") { $0.pending = [p] }
        r.clock.advance(by: 5)
        try r.coordinator.accept("p1", ops: [0])
        let added = try XCTUnwrap(r.controller.store.patchLog.last?.assignedIDs["a"])
        XCTAssertEqual(r.controller.store.pending.first?.ops, [.updateNode(id: added, fields: NodeFields(progress: 20))])
        try r.coordinator.accept("p1")
        XCTAssertEqual(r.controller.store.nodes[added]?.progress, 20)
    }

    func testAQueuedInitiativeDoesNotHoldBackAMessageBehindIt() async throws {
        let fake = FakeAdapter(.held)
        let r = try rig(fake)
        r.controller.send(.startSession)                                   // IDLE: messages run, initiatives wait
        r.coordinator.send(message: "first")
        while !(await fake.isWaiting) { await Task.yield() }
        r.coordinator.run(.initiative([]))
        r.coordinator.send(message: "second")
        await fake.release("")
        while !(await fake.isWaiting) { await Task.yield() }               // the second message is running
        let prompts = await fake.prompts
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].contains("second"))
        await fake.release("")
        await r.coordinator.waitUntilIdle()
    }

    func testUndoDoesNotReachAcrossACommit() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        let n1 = r.ids["n1"]!
        r.controller.send(.startSession)
        try r.controller.apply([.updateNode(id: n1, fields: NodeFields(title: "renamed"))])
        XCTAssertTrue(r.controller.canUndo)
        r.controller.send(.commit(doing: n1, next: r.ids["n2"]!))
        XCTAssertFalse(r.controller.canUndo)
        try r.controller.undo()                                             // a no-op, not a revert to `open`
        XCTAssertEqual(r.controller.store.doing?.id, n1)
        XCTAssertEqual(r.controller.store.nodes[n1]?.title, "renamed")
    }
}

extension InitiativeSchedulerTests {
    func testASnoozedNodeIsNotNudgedUntilTheSnoozeLapses() async throws {
        let r = try rig()
        let n1 = r.ids["n1"]!
        r.scheduler.snooze(node: n1, until: noon.addingTimeInterval(3600))
        XCTAssertTrue(r.scheduler.nodeSnoozed(n1))
        r.scheduler.start()
        r.clock.advance(by: InitiativeScheduler.coalesceWindow)
        await r.coordinator.waitUntilIdle()
        var p = await prompts(r)
        XCTAssertEqual(p.count, 0)
        r.clock.advance(by: 3600)                                          // lapsed; the next evaluation nudges
        await r.coordinator.waitUntilIdle()
        p = await prompts(r)
        XCTAssertEqual(p.count, 1)
        XCTAssertFalse(r.scheduler.nodeSnoozed(n1))
    }
}
