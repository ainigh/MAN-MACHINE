import XCTest
import MpmCore
@testable import MpmHost

/// A scriptable adapter: answers at once, waits to be released, or never answers.
actor FakeAdapter: ModelAdapter {
    enum Mode { case immediate(String), held, never }
    nonisolated var name: String { "fake" }
    private var mode: Mode
    private var waiting: CheckedContinuation<String, Never>?
    private(set) var prompts: [String] = []

    init(_ mode: Mode) { self.mode = mode }

    func complete(_ prompt: String, deadline: Date) async throws -> String {
        prompts.append(prompt)
        switch mode {
        case .immediate(let s): return s
        case .held: return await withCheckedContinuation { waiting = $0 }
        case .never:
            try await Task.sleep(for: .seconds(3600))
            return ""
        }
    }

    func release(_ text: String) { waiting?.resume(returning: text); waiting = nil }
    var isWaiting: Bool { waiting != nil }
}

@MainActor
final class ModelTurnTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mpm-\(UUID().uuidString)")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    struct Rig {
        let clock: ManualClock
        let controller: SessionController
        let coordinator: ModelTurnCoordinator
        let persistence: Persistence
        let ids: [String: NodeID]
    }

    func rig(_ adapter: ModelAdapter) throws -> Rig {
        var settings = Settings.default
        settings.session = SessionConfig(R: 360, r: 3, Ls: 900, Lb: 120)
        var store = Store(rootTitle: "GOAL", now: t0, settings: settings, rootID: "root")
        var ids: [String: NodeID] = [:]
        for (i, name) in ["n1", "n2", "n3", "n4"].enumerated() {
            ids[name] = try store.apply([.add(name, under: "root", tmp: name)], author: .man,
                                        now: t0.addingTimeInterval(Double(i))).entry.assignedIDs[name]!
        }
        let p = Persistence(directory: dir)
        _ = try p.load(now: t0)
        let clock = ManualClock(t0.addingTimeInterval(10))
        let coord = ModelTurnCoordinator(adapter: adapter)
        let c = SessionController(store: store, clock: clock, persistence: p, coordinator: coord)
        coord.controller = c
        return Rig(clock: clock, controller: c, coordinator: coord, persistence: p, ids: ids)
    }

    func envelope(say: String, patch: String = "[]") -> String {
        "Sure.\n```envelope\n{\"say\":\"\(say)\",\"ask\":null,\"patch\":\(patch),\"next\":null}\n```"
    }

    /// Runs round 1 to STATUS: commit n1/n2, mark n1 done, finish. Returns the STATUS end.
    func toStatus(_ r: Rig) -> Date {
        r.controller.send(.startSession)
        r.controller.send(.commit(doing: r.ids["n1"]!, next: r.ids["n2"]!))
        r.clock.advance(by: 100)
        try! r.controller.apply([.setStatus(r.ids["n1"]!, .done)])
        r.controller.send(.finish)
        XCTAssertEqual(r.controller.state, .status)
        return r.controller.store.session!.phaseEnd!
    }

    func turnLog(_ r: Rig) -> [TurnLogRecord] {
        r.persistence.flush()
        return JSONLines.read(TurnLogRecord.self, from: r.persistence.turnLogURL).values
    }

    // (a) answers in time → held → rendered at STRATEGY
    func testAnswerInTimeIsHeldThenRenderedAtStrategy() async throws {
        let patch = "[{\"op\":\"update_node\",\"id\":\"ID\",\"fields\":{\"status\":\"next\"}}]"
        let fake = FakeAdapter(.held)
        let x = try rig(fake)
        let statusEnd = toStatus(x)
        while !(await fake.isWaiting) { await Task.yield() }
        XCTAssertTrue(x.coordinator.card.isEmpty)                          // silent: nothing shown in STATUS
        await fake.release(envelope(say: "One cleared. Take n3 next.",
                                    patch: patch.replacingOccurrences(of: "ID", with: x.ids["n3"]!)))
        await x.coordinator.waitUntilIdle()
        XCTAssertEqual(x.controller.store.held.count, 1)
        XCTAssertTrue(x.coordinator.card.isEmpty)
        XCTAssertTrue(x.controller.store.pending.isEmpty)

        x.clock.advance(to: statusEnd)
        XCTAssertEqual(x.controller.state, .strategy)
        XCTAssertEqual(x.coordinator.card.map(\.text), ["One cleared. Take n3 next."])
        XCTAssertEqual(x.controller.store.pending.count, 1)
        XCTAssertTrue(x.controller.store.held.isEmpty)
        let log = turnLog(x)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0].deadlineMet, true)
        XCTAssertEqual(log[0].ladderStep, 1)
    }

    // (b) answers late → say dropped, patch pending next round
    func testLateAnswerDropsSayAndKeepsPatchForTheNextStrategy() async throws {
        let fake = FakeAdapter(.held)
        let r = try rig(fake)
        let statusEnd = toStatus(r)
        while !(await fake.isWaiting) { await Task.yield() }
        r.clock.advance(to: statusEnd.addingTimeInterval(5))               // into STRATEGY; deadline missed
        XCTAssertEqual(r.controller.state, .strategy)
        let patch = "[{\"op\":\"update_node\",\"id\":\"\(r.ids["n4"]!)\",\"fields\":{\"progress\":10}}]"
        await fake.release(envelope(say: "Too late to matter.", patch: patch))
        await r.coordinator.waitUntilIdle()
        XCTAssertTrue(r.coordinator.card.isEmpty)
        XCTAssertTrue(r.controller.store.pending.isEmpty)
        XCTAssertEqual(r.controller.store.held.map(\.say), [""])
        XCTAssertEqual(turnLog(r).last?.deadlineMet, false)

        // Next round's STRATEGY shows the patch as a proposal, without the say.
        r.controller.send(.commit(doing: r.ids["n2"]!, next: r.ids["n3"]!))
        XCTAssertEqual(r.controller.state, .work)
        r.clock.advance(by: 10)
        r.controller.send(.finish)
        r.clock.advance(to: r.controller.store.session!.phaseEnd!)
        XCTAssertEqual(r.controller.state, .strategy)
        XCTAssertEqual(r.controller.store.pending.count, 1)
        XCTAssertTrue(r.coordinator.card.isEmpty)
    }

    // (c) never answers → nothing happens, session unaffected, one turn-log line with deadline_met false
    func testModelThatNeverAnswersLeavesAWorkingSession() async throws {
        let r = try rig(FakeAdapter(.never))
        let statusEnd = toStatus(r)
        r.clock.advance(to: statusEnd)
        XCTAssertEqual(r.controller.state, .strategy)
        XCTAssertTrue(r.coordinator.card.isEmpty)
        r.clock.advance(by: 45)                                            // auto-commit, next round
        XCTAssertEqual(r.controller.state, .work)
        r.clock.advance(to: statusEnd.addingTimeInterval(ModelTurnCoordinator.lateLimit + 1))
        await r.coordinator.waitUntilIdle()
        let log = turnLog(r)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0].deadlineMet, false)
        XCTAssertTrue(log[0].outcome.hasPrefix("failed"))
        XCTAssertTrue(r.controller.store.held.isEmpty)
        XCTAssertTrue(r.controller.store.pending.isEmpty)
        XCTAssertFalse(r.coordinator.busy)
    }

    // (d) prose only → ladder step 5, say shown
    func testProseOnlyBecomesSay() async throws {
        let r = try rig(FakeAdapter(.immediate("Good round. Keep the momentum on n2.")))
        r.controller.updateSettings({ var s = r.controller.store.settings; s.repairPass = false; return s }())
        let statusEnd = toStatus(r)
        await r.coordinator.waitUntilIdle()
        r.clock.advance(to: statusEnd)
        XCTAssertEqual(r.coordinator.card.map(\.text), ["Good round. Keep the momentum on n2."])
        XCTAssertEqual(turnLog(r).last?.ladderStep, 5)
    }

    // (e) patch touching a no_suggest node → whole patch rejected, reason logged, say still shown
    func testPatchTouchingALockedNodeIsRejectedWholeButSayIsShown() async throws {
        let fake = FakeAdapter(.held)
        let r = try rig(fake)
        try r.controller.apply([.updateNode(id: r.ids["n4"]!, fields: NodeFields(flags: [Node.flagNoSuggest]))])
        let statusEnd = toStatus(r)
        while !(await fake.isWaiting) { await Task.yield() }
        let patch = "[{\"op\":\"update_node\",\"id\":\"\(r.ids["n3"]!)\",\"fields\":{\"progress\":50}},{\"op\":\"cross_out\",\"id\":\"\(r.ids["n4"]!)\"}]"
        await fake.release(envelope(say: "Drop n4.", patch: patch))
        await r.coordinator.waitUntilIdle()
        r.clock.advance(to: statusEnd)
        XCTAssertEqual(r.coordinator.card.map(\.text), ["Drop n4."])
        XCTAssertTrue(r.controller.store.pending.isEmpty)
        let line = try XCTUnwrap(turnLog(r).last)
        XCTAssertTrue(line.validation?.contains("locked") == true, line.validation ?? "")
        XCTAssertTrue(line.outcome.contains("patch rejected"))
    }

    // MARK: Disposition and routing

    func testAcceptRejectAndLock() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        r.controller.send(.startSession)
        let p = Proposal(id: "p1", turnID: "t1", at: r.clock.now(),
                         ops: [.setStatus(r.ids["n1"]!, .doing), .setStatus(r.ids["n2"]!, .next)], say: "Start with n1.")
        r.controller.updateModelState("test") { $0.pending = [p] }
        try r.coordinator.accept("p1", ops: [0])
        XCTAssertEqual(r.controller.store.doing?.id, r.ids["n1"])
        XCTAssertEqual(r.controller.store.pending.first?.ops.count, 1)
        XCTAssertEqual(r.controller.store.patchLog.last?.author, .model)
        XCTAssertEqual(r.controller.state, .idle)
        try r.coordinator.accept("p1")                                     // both slots set → commit by patch
        XCTAssertEqual(r.controller.state, .work)
        XCTAssertTrue(r.controller.store.pending.isEmpty)
        XCTAssertEqual(turnLog(r).filter { $0.trigger == "disposition" }.count, 2)

        let q = Proposal(id: "p2", turnID: "t2", at: r.clock.now(), ops: [.crossOut(id: r.ids["n3"]!)], say: "")
        r.controller.updateModelState("test") { $0.pending = [q] }
        r.coordinator.reject("p2")
        XCTAssertEqual(r.controller.store.declined.map(\.summary), ["cross out “n3”"])
        XCTAssertEqual(r.controller.store.declined.first?.nodeIDs, [r.ids["n3"]!])

        let l = Proposal(id: "p3", turnID: "t3", at: r.clock.now(), ops: [.crossOut(id: r.ids["n4"]!)], say: "")
        r.controller.updateModelState("test") { $0.pending = [l] }
        try r.coordinator.lock("p3")
        XCTAssertTrue(r.controller.store.nodes[r.ids["n4"]!]!.noSuggest)
        XCTAssertEqual(r.controller.store.patchLog.last?.author, .man)
    }

    func testStaleOpsTouchingChangedNodesAreBlocked() async throws {
        let r = try rig(FakeAdapter(.immediate("")))
        let p = Proposal(id: "p1", turnID: "t1", at: r.clock.now(),
                         ops: [.updateNode(id: r.ids["n1"]!, fields: NodeFields(progress: 50)),
                               .updateNode(id: r.ids["n2"]!, fields: NodeFields(progress: 20))], say: "")
        r.controller.updateModelState("test") { $0.pending = [p] }
        r.clock.advance(by: 1)
        try r.controller.apply([.updateNode(id: r.ids["n1"]!, fields: NodeFields(title: "n1 renamed"))])
        XCTAssertTrue(r.coordinator.isStale(p))
        XCTAssertThrowsError(try r.coordinator.accept("p1")) { e in
            XCTAssertEqual(e as? ModelTurnCoordinator.DispositionError, .staleOp(r.ids["n1"]!))
        }
        try r.coordinator.accept("p1", ops: [1])                           // the untouched op still goes through
        XCTAssertEqual(r.controller.store.nodes[r.ids["n2"]!]?.progress, 20)
    }

    func testMessageDuringWorkWaitsForStrategy() async throws {
        let fake = FakeAdapter(.immediate(envelope(say: "Noted.")))
        let r = try rig(fake)
        r.controller.send(.startSession)
        r.controller.send(.commit(doing: r.ids["n1"]!, next: r.ids["n2"]!))
        r.coordinator.send(message: "remind me to call the bank")
        await r.coordinator.waitUntilIdle()
        let promptsDuringWork = await fake.prompts.count
        XCTAssertEqual(promptsDuringWork, 0)                               // SPEC §13 #11: no turn in WORK
        r.controller.send(.finish)                                          // the phase turn runs (STATUS)
        await r.coordinator.waitUntilIdle()
        r.clock.advance(to: r.controller.store.session!.phaseEnd!)          // STRATEGY: held + queued message
        await r.coordinator.waitUntilIdle()
        let prompts = await fake.prompts
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[1].contains("human: remind me to call the bank"))
        XCTAssertEqual(r.coordinator.card.map(\.text), ["Noted.", "Noted."])
    }

    func testAnswerCarriesTheQuestionAndClearsIt() async throws {
        let fake = FakeAdapter(.immediate("```envelope\n{\"say\":\"\",\"ask\":\"Which first, n3 or n4?\",\"patch\":[],\"next\":null}\n```"))
        let r = try rig(fake)
        r.coordinator.send(message: "what now?")
        await r.coordinator.waitUntilIdle()
        XCTAssertEqual(r.controller.store.question?.text, "Which first, n3 or n4?")
        r.coordinator.send(message: "n4")
        XCTAssertNil(r.controller.store.question)
        await r.coordinator.waitUntilIdle()
        let prompts = await fake.prompts
        XCTAssertTrue(prompts[1].contains("trigger: answer"))
        XCTAssertTrue(prompts[1].contains("pending question (asked earlier): Which first, n3 or n4?"))
    }

    func testNoModelMeansNoTurnsAndAnIdenticalSession() async throws {
        let r = try rig(NullAdapter())
        let statusEnd = toStatus(r)
        await r.coordinator.waitUntilIdle()
        r.clock.advance(to: statusEnd)
        XCTAssertEqual(r.controller.state, .strategy)
        XCTAssertTrue(turnLog(r).isEmpty)
    }

    func testAnthropicResponseParsing() async throws {
        let ok = Data(#"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"```envelope\n{}\n```"}],"stop_reason":"end_turn"}"#.utf8)
        XCTAssertEqual(try AnthropicAdapter.text(from: ok), "```envelope\n{}\n```")
        let refused = Data(#"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}"#.utf8)
        XCTAssertThrowsError(try AnthropicAdapter.text(from: refused)) { XCTAssertEqual($0 as? ModelError, .refused("cyber")) }
        let body = AnthropicAdapter.requestBody(prompt: "p", model: "claude-opus-5-5", effort: "low")
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
    }
}
