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

/// An adapter that never answers and ignores cancellation, as a wedged connection can.
actor DeafAdapter: ModelAdapter {
    nonisolated var name: String { "deaf" }
    private var waiting: [CheckedContinuation<String, Never>] = []
    var calls: Int { waiting.count }
    func complete(_ prompt: String, deadline: Date) async throws -> String {
        await withCheckedContinuation { waiting.append($0) }
    }
    func releaseAll() { for w in waiting { w.resume(returning: "") }; waiting = [] }
}

/// Bugs found reviewing the host layer against SPEC §8 and the hard rules.
extension ModelTurnTests {

    func testAnAdapterThatIgnoresCancellationDoesNotBlockLaterTurns() async throws {
        let deaf = DeafAdapter()
        let late = Date().addingTimeInterval(86_400)                       // real time has caught up with the limit
        let r = try rig(deaf, realNow: { late })
        let statusEnd = toStatus(r)
        while await deaf.calls < 1 { await Task.yield() }
        r.clock.advance(to: statusEnd.addingTimeInterval(ModelTurnCoordinator.lateLimit + 1))
        XCTAssertFalse(r.coordinator.busy, "an abandoned turn is over even if the adapter never returns")
        let log = turnLog(r)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.deadlineMet, false)
        XCTAssertTrue(log.first?.outcome.hasPrefix("failed") == true, log.first?.outcome ?? "")

        // The next round's phase turn starts instead of being skipped (CLAUDE.md hard rule 4).
        XCTAssertEqual(r.controller.state, .work)
        r.controller.send(.finish)
        XCTAssertEqual(r.controller.state, .status)
        for _ in 0..<200 where await deaf.calls < 2 { await Task.yield() }
        let calls = await deaf.calls
        XCTAssertEqual(calls, 2)
        await deaf.releaseAll()
    }

    func testAMessageAfterTheQuestionExpiredIsNotRoutedAsItsAnswer() async throws {
        let fake = FakeAdapter(.immediate("```envelope\n{\"say\":\"\",\"ask\":\"Which first, n3 or n4?\",\"patch\":[],\"next\":null}\n```"))
        let r = try rig(fake)
        r.coordinator.send(message: "what now?")
        await r.coordinator.waitUntilIdle()
        let q = try XCTUnwrap(r.controller.store.question)
        r.clock.advance(to: q.expiresAt.addingTimeInterval(3600))         // the next morning
        r.coordinator.send(message: "plan the day")
        await r.coordinator.waitUntilIdle()
        let prompts = await fake.prompts
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].contains("trigger: message"), prompts[1])
        XCTAssertFalse(prompts[1].contains("pending question"), "SPEC §8.4: expiry clears the slot")
    }

    func testAQuestionAskedInIdleMidSessionDoesNotExpireAtOnce() async throws {
        let fake = FakeAdapter(.immediate(""))
        let r = try rig(fake)
        r.controller.send(.startSession)
        r.controller.send(.commit(doing: r.ids["n1"]!, next: r.ids["n2"]!))
        r.clock.advance(by: 10)
        try r.controller.apply([.setStatus(r.ids["n3"]!, .done), .setStatus(r.ids["n4"]!, .done)])
        try r.controller.apply([.setStatus(r.ids["n1"]!, .done)])          // n2 promoted
        try r.controller.apply([.setStatus(r.ids["n2"]!, .done)])
        r.controller.send(.finish)
        await r.coordinator.waitUntilIdle()
        r.clock.advance(to: r.controller.store.session!.phaseEnd!)         // STRATEGY
        r.clock.advance(to: r.controller.store.session!.phaseEnd!)         // auto-commit finds nothing open: IDLE
        XCTAssertEqual(r.controller.state, .idle)
        r.clock.advance(by: 30)

        let ask = FakeAdapter(.immediate("```envelope\n{\"say\":\"\",\"ask\":\"Add the next step?\",\"patch\":[],\"next\":null}\n```"))
        r.coordinator.setAdapter(ask, settings: r.coordinator.settings)
        r.coordinator.send(message: "all done")
        await r.coordinator.waitUntilIdle()
        let q = try XCTUnwrap(r.controller.store.question)
        XCTAssertGreaterThan(q.expiresAt, r.clock.now(), "IDLE's phaseEnd is the last STRATEGY's, already past")
    }

    func testUndoDoesNotReachAcrossACommitByPatch() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        let n1 = r.ids["n1"]!, n2 = r.ids["n2"]!
        r.controller.send(.startSession)
        try r.controller.apply([.setStatus(n1, .doing)])
        try r.controller.apply([.setStatus(n2, .next)])                    // both slots set: the round starts
        XCTAssertEqual(r.controller.state, .work)
        XCTAssertFalse(r.controller.canUndo)
        try r.controller.undo()
        XCTAssertEqual(r.controller.store.doing?.id, n1)
        XCTAssertEqual(r.controller.store.next?.id, n2)
    }
}

extension MonitorTests {
    func testMessagesAndDispositionsFromTheManAreDrawnEdges() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        r.coordinator.send(message: "hello")
        await r.coordinator.waitUntilIdle()
        XCTAssertTrue(r.monitor.events.contains { $0.from == .man && $0.to == .coordinator })
        assertEdgesDrawn(r.monitor)
    }
}

extension GraphSceneTests {
    func testAFinishedNodeWithLiveChildrenDoesNotCollapse() throws {
        var (s, id) = try store()
        try s.apply([.setStatus(id["api"]!, .done)], author: .man, now: t0.addingTimeInterval(10))   // deploy still open
        XCTAssertEqual(GraphScene.collapsibleRoots(s), [])

        try s.apply([.setStatus(id["api"]!, .open)], author: .man, now: t0.addingTimeInterval(11))
        try s.apply([.crossOut(id: id["api"]!)], author: .man, now: t0.addingTimeInterval(12))
        XCTAssertEqual(GraphScene.collapsibleRoots(s), [id["api"]!])
        try s.apply([.restore(id: id["deploy"]!)], author: .man, now: t0.addingTimeInterval(13))   // back under a crossed-out parent
        XCTAssertEqual(GraphScene.collapsibleRoots(s), [])
    }
}

extension PersistenceTests {
    func testAnUnreadableSnapshotIsLeftInPlaceWhenTheLogCannotBeReplayed() throws {
        let p = persistence()
        var s = try p.load(now: t0)
        try buildHistory(&s, from: t0)
        p.record(s); p.flush()
        var lines = try String(contentsOf: p.patchLogURL, encoding: .utf8).split(separator: "\n")
        XCTAssertGreaterThan(lines.count, 2)
        lines.remove(at: 1)                                                // a gap in the middle of the log
        try (lines.joined(separator: "\n") + "\n").write(to: p.patchLogURL, atomically: true, encoding: .utf8)
        let garbage = Data("not json".utf8)
        try garbage.write(to: p.storeURL)

        XCTAssertThrowsError(try persistence().load(now: t0 + 100)) { e in
            XCTAssertEqual(e as? PersistenceError, .logGap(expected: 2, found: 3))
        }
        XCTAssertEqual(try Data(contentsOf: p.storeURL), garbage, "a throwing load leaves the files as they were")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("store.corrupt-") })
    }
}
