import XCTest
import MpmCore
@testable import MpmHost

@MainActor
final class InitiativeSchedulerTests: XCTestCase {
    /// 2027-01-15 12:00 UTC: outside the default quiet hours (22–8).
    let noon = Date(timeIntervalSince1970: 1_800_000_000 + 4 * 3600)
    var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mpm-\(UUID().uuidString)")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    struct Rig {
        let clock: ManualClock
        let controller: SessionController
        let coordinator: ModelTurnCoordinator
        let scheduler: InitiativeScheduler
        let fake: FakeAdapter
        let ids: [String: NodeID]
    }

    func rig(start: Date? = nil, overdue: Bool = true) throws -> Rig {
        let start = start ?? noon
        var settings = Settings.default
        settings.timezone = "UTC"
        var store = Store(rootTitle: "GOAL", now: start.addingTimeInterval(-86_400 * 3), settings: settings, rootID: "root")
        var ids: [String: NodeID] = [:]
        for name in ["n1", "n2"] {
            ids[name] = try store.apply([.add(name, under: "root", tmp: name)], author: .man,
                                        now: start.addingTimeInterval(-86_400 * 3)).entry.assignedIDs[name]!
        }
        if overdue {
            try store.apply([.updateNode(id: ids["n1"]!, fields: NodeFields(due: start.addingTimeInterval(-86_400)))],
                            author: .man, now: start.addingTimeInterval(-86_400 * 2))
        }
        let p = Persistence(directory: dir)
        _ = try p.load(now: start)
        let clock = ManualClock(start)
        let fake = FakeAdapter(.immediate("```envelope\n{\"say\":\"n1 is overdue.\",\"ask\":null,\"patch\":[],\"next\":null}\n```"))
        let coord = ModelTurnCoordinator(adapter: fake)
        let c = SessionController(store: store, clock: clock, persistence: p, coordinator: coord)
        coord.controller = c
        let s = InitiativeScheduler(controller: c, coordinator: coord, persistence: p, settings: HostSettings())
        return Rig(clock: clock, controller: c, coordinator: coord, scheduler: s, fake: fake, ids: ids)
    }

    func prompts(_ r: Rig) async -> [String] { await r.fake.prompts }

    func testLaunchWithAnOverdueNodeNudgesOncePerDay() async throws {
        let r = try rig()
        r.scheduler.start()
        r.clock.advance(by: InitiativeScheduler.coalesceWindow)
        await r.coordinator.waitUntilIdle()
        var p = await prompts(r)
        XCTAssertEqual(p.count, 1)
        XCTAssertTrue(p[0].contains("trigger: initiative: overdue \(r.ids["n1"]!)"))
        XCTAssertEqual(r.coordinator.card.map(\.text), ["n1 is overdue."])   // no session: rendered at once

        r.clock.advance(by: 4 * 3600)                                      // 16 evaluations later, same day
        await r.coordinator.waitUntilIdle()
        p = await prompts(r)
        XCTAssertEqual(p.count, 1)

        r.clock.advance(by: 20 * 3600)                                     // next day, after quiet hours
        await r.coordinator.waitUntilIdle()
        p = await prompts(r)
        XCTAssertEqual(p.count, 2)
    }

    func testTwoTriggersWithinAMinuteCoalesce() async throws {
        let r = try rig()
        try r.controller.apply([.addDep(id: r.ids["n2"]!, dep: r.ids["n1"]!)])
        r.scheduler.start()                                                // overdue n1
        r.clock.advance(by: 30)
        try r.controller.apply([.setStatus(r.ids["n1"]!, .done)])          // unblocks n2, 30 s later
        r.clock.advance(by: 60)
        await r.coordinator.waitUntilIdle()
        let p = await prompts(r)
        XCTAssertEqual(p.count, 1)
        XCTAssertTrue(p[0].contains("trigger: initiative: overdue \(r.ids["n1"]!), unblocked \(r.ids["n2"]!)"))
    }

    func testQuietHoursDeferTheNudgeToTheWindowEnd() async throws {
        let late = noon.addingTimeInterval(11 * 3600)                      // 23:00 UTC
        let r = try rig(start: late)
        r.scheduler.start()
        r.clock.advance(by: 3600)
        await r.coordinator.waitUntilIdle()
        var p = await prompts(r)
        XCTAssertEqual(p.count, 0)
        XCTAssertTrue(r.scheduler.lastDecision?.contains("quiet hours") == true)
        r.clock.advance(to: noon.addingTimeInterval(20 * 3600 + 1))        // 08:00 next day
        await r.coordinator.waitUntilIdle()
        p = await prompts(r)
        XCTAssertEqual(p.count, 1)
    }

    func testModelNextInASessionWaitsAndScheduleFiresAfterTheSession() async throws {
        let r = try rig(overdue: false)
        r.scheduler.start()
        r.controller.send(.startSession)
        r.controller.send(.commit(doing: r.ids["n1"]!, next: r.ids["n2"]!))
        r.scheduler.modelAskedNext(r.clock.now().addingTimeInterval(10), turnID: "t1")
        let entry = try XCTUnwrap(r.controller.store.schedule.first)
        XCTAssertEqual(entry.source, .model)
        XCTAssertEqual(entry.at, r.controller.store.session!.phaseEnd)     // clamped (no earlier than the round)
        r.clock.advance(by: 600)
        await r.coordinator.waitUntilIdle()
        let during = await prompts(r)
        XCTAssertEqual(during.filter { $0.contains("trigger: schedule") }.count, 0)
        r.controller.send(.endSession)
        await r.coordinator.waitUntilIdle()
        let after = await prompts(r)
        XCTAssertEqual(after.filter { $0.contains("trigger: schedule (model)") }.count, 1)
    }

    func testSnoozeAndDisabledRules() async throws {
        let r = try rig()
        r.scheduler.setRule("overdue", enabled: false)
        r.scheduler.start()
        r.clock.advance(by: 120)
        await r.coordinator.waitUntilIdle()
        var p = await prompts(r)
        XCTAssertEqual(p.count, 0)
        r.scheduler.setRule("overdue", enabled: true)
        r.scheduler.snooze(until: noon.addingTimeInterval(3600))
        r.scheduler.evaluate()
        r.clock.advance(by: 120)
        await r.coordinator.waitUntilIdle()
        p = await prompts(r)
        XCTAssertEqual(p.count, 0)
        r.clock.advance(to: noon.addingTimeInterval(3601))
        await r.coordinator.waitUntilIdle()
        p = await prompts(r)
        XCTAssertEqual(p.count, 1)
    }
}
