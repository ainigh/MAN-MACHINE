import XCTest
@testable import MpmCore

final class ProjectionTests: XCTestCase {
    func testPhaseProjectionCarriesSessionAndDiff() throws {
        let (store, id) = Fixtures.starting()
        var sim = Simulator(store: store, now: Fixtures.t0)
        sim.send(.startSession); sim.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        sim.advance(100)
        try sim.patch([.setStatus(id["n1"]!, .done), .updateNode(id: id["n2"]!, fields: NodeFields(aiNote: "batch on Fridays"))])
        sim.send(.finish)
        let p = Projection.project(sim.store, trigger: .phase, now: sim.now)
        XCTAssertTrue(p.contains("trigger: phase"))
        XCTAssertTrue(p.contains("session: round 1, R 6 min, z 0/3, x 1, status 45 s, seated 1:40"))
        XCTAssertTrue(p.contains("round diff: \(id["n1"]!) open→done, \(id["n2"]!) open→doing"))
        XCTAssertTrue(p.contains("[\(id["n1"]!)] n1  [done]"))
        XCTAssertTrue(p.contains("(doing, updated today)"))
        XCTAssertTrue(p.contains("note: batch on Fridays"))
        XCTAssertTrue(p.contains("[root] GOAL"))
    }

    func testLockedAndCrossedOutRendering() throws {
        var (s, id) = Fixtures.starting()
        try s.apply([.updateNode(id: id["n1"]!, fields: NodeFields(flags: [Node.flagNoSuggest])), .crossOut(id: id["n2"]!),
                     .add("k", under: id["n2"]!)], author: .man, now: Fixtures.t0)
        let p = Projection.renderGraph(s, now: Fixtures.t0)
        XCTAssertTrue(p.contains("n1  [locked]"))
        XCTAssertTrue(p.contains("n2  [x] (1 children)"))
        XCTAssertFalse(p.contains("] k "))   // collapsed
    }

    func testCapDropsFarOpenNodesFirst() throws {
        var (s, id) = Fixtures.starting()
        var settings = s.settings; settings.projectionMaxChars = 300; s.settings = settings
        try s.apply([.setStatus(id["n1"]!, .doing)], author: .man, now: Fixtures.t0)
        for i in 0..<4 { try s.apply([.add("far\(i)", under: id["n4"]!)], author: .man, now: Fixtures.t0.addingTimeInterval(Double(i))) }
        let p = Projection.renderGraph(s, now: Fixtures.t0)
        XCTAssertTrue(p.count <= 300 + 60)
        XCTAssertTrue(p.contains("n1  (doing"))
    }

    func testInitiativeRules() throws {
        var (s, id) = Fixtures.starting()
        let now = Fixtures.t0.addingTimeInterval(30 * 86_400)
        try s.apply([.updateNode(id: id["n1"]!, fields: NodeFields(due: Fixtures.t0)),
                     .updateNode(id: id["n2"]!, fields: NodeFields(due: now.addingTimeInterval(86_400))),
                     .setStatus(id["n3"]!, .doing)], author: .man, now: Fixtures.t0)
        let hits = InitiativeRules.evaluate(s, now: now)
        XCTAssertEqual(Set(hits.map(\.rule)), ["overdue", "due_soon", "stale", "drift"])
    }
}
