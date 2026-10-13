import XCTest
@testable import MpmCore

final class StoreTests: XCTestCase {
    let t = Fixtures.t0

    func testSlotDisplacement() throws {
        var (s, id) = Fixtures.starting()
        try s.apply([.setStatus(id["n1"]!, .doing), .setStatus(id["n2"]!, .next)], author: .man, now: t)
        try s.apply([.setStatus(id["n3"]!, .doing)], author: .man, now: t)
        XCTAssertEqual(s.nodes[id["n1"]!]?.status, .open)
        XCTAssertEqual(s.doing?.id, id["n3"])
        XCTAssertEqual(s.nodes.values.filter { $0.status == .doing }.count, 1)
        // A node can't be both: setting next on the doing node moves it out of doing.
        try s.apply([.setStatus(id["n3"]!, .next)], author: .man, now: t)
        XCTAssertNil(s.doing); XCTAssertEqual(s.next?.id, id["n3"]); XCTAssertEqual(s.nodes[id["n2"]!]?.status, .open)
    }

    func testBlockedIsDerived() throws {
        var (s, id) = Fixtures.starting()
        XCTAssertThrowsError(try s.apply([.setStatus(id["n1"]!, .blocked)], author: .man, now: t))
        try s.apply([.addDep(id: id["n2"]!, dep: id["n1"]!)], author: .man, now: t)
        XCTAssertEqual(s.nodes[id["n2"]!]?.status, .blocked)
        XCTAssertThrowsError(try s.apply([.setStatus(id["n2"]!, .open)], author: .man, now: t))
        XCTAssertThrowsError(try s.apply([.setStatus(id["n2"]!, .doing)], author: .man, now: t))
        // next is allowed when the only unfinished dep is D
        try s.apply([.setStatus(id["n1"]!, .doing)], author: .man, now: t)
        try s.apply([.setStatus(id["n2"]!, .next)], author: .man, now: t)
        XCTAssertNoThrow(try Engine.validateCommit(d: id["n1"]!, n: id["n2"]!, store: s))
        XCTAssertThrowsError(try Engine.validateCommit(d: id["n2"]!, n: id["n1"]!, store: s))
        // clearing the dep unblocks and reports it
        try s.apply([.addDep(id: id["n4"]!, dep: id["n3"]!)], author: .man, now: t)
        XCTAssertEqual(s.nodes[id["n4"]!]?.status, .blocked)
        let r = try s.apply([.setStatus(id["n3"]!, .done)], author: .man, now: t)
        XCTAssertEqual(r.unblocked, [id["n4"]!])
        XCTAssertEqual(s.nodes[id["n4"]!]?.status, .open)
        // a dep that would block the doing node is refused
        XCTAssertThrowsError(try s.apply([.addDep(id: id["n1"]!, dep: id["n4"]!)], author: .man, now: t))
    }

    func testCycles() throws {
        var (s, id) = Fixtures.starting()
        try s.apply([.addDep(id: id["n2"]!, dep: id["n1"]!)], author: .man, now: t)
        XCTAssertThrowsError(try s.apply([.addDep(id: id["n1"]!, dep: id["n2"]!)], author: .man, now: t))
        XCTAssertThrowsError(try s.apply([.addDep(id: id["n1"]!, dep: id["n1"]!)], author: .man, now: t))
        try s.apply([.moveNode(id: id["n2"]!, parent: id["n1"]!)], author: .man, now: t)
        XCTAssertThrowsError(try s.apply([.moveNode(id: id["n1"]!, parent: id["n2"]!)], author: .man, now: t))
        XCTAssertThrowsError(try s.apply([.moveNode(id: "root", parent: id["n1"]!)], author: .man, now: t))
    }

    func testCrossOutCascadesToUnfinishedOnly() throws {
        var (s, id) = Fixtures.starting()
        let r = try s.apply([.add("c1", under: id["n1"]!, tmp: "c1"), .add("c2", under: id["n1"]!, tmp: "c2"),
                             .add("g1", under: Op.tmp("c1"), tmp: "g1")], author: .man, now: t)
        let c1 = r.entry.assignedIDs["c1"]!, c2 = r.entry.assignedIDs["c2"]!, g1 = r.entry.assignedIDs["g1"]!
        try s.apply([.setStatus(c2, .done)], author: .man, now: t)
        try s.apply([.crossOut(id: id["n1"]!)], author: .man, now: t)
        XCTAssertEqual(s.nodes[id["n1"]!]?.status, .crossedOut)
        XCTAssertEqual(s.nodes[c1]?.status, .crossedOut)
        XCTAssertEqual(s.nodes[g1]?.status, .crossedOut)
        XCTAssertEqual(s.nodes[c2]?.status, .done)
        try s.apply([.restore(id: c1)], author: .man, now: t)
        XCTAssertEqual(s.nodes[c1]?.status, .open)
        XCTAssertEqual(s.nodes[g1]?.status, .crossedOut)   // no cascade on restore
    }

    func testRemoveNodeIsTypoRepairOnly() throws {
        var (s, id) = Fixtures.starting()
        XCTAssertThrowsError(try s.apply([.removeNode(id: id["n1"]!)], author: .model, now: t))
        try s.apply([.setStatus(id["n1"]!, .doing)], author: .man, now: t)
        try s.apply([.setStatus(id["n1"]!, .open)], author: .man, now: t)
        XCTAssertThrowsError(try s.apply([.removeNode(id: id["n1"]!)], author: .man, now: t))   // has held a slot
        try s.apply([.add("k", under: id["n2"]!)], author: .man, now: t)
        XCTAssertThrowsError(try s.apply([.removeNode(id: id["n2"]!)], author: .man, now: t))   // not a leaf
        try s.apply([.removeNode(id: id["n3"]!)], author: .man, now: t)
        XCTAssertNil(s.nodes[id["n3"]!])
    }

    func testModelRestrictions() throws {
        var (s, id) = Fixtures.starting()
        try s.apply([.updateNode(id: id["n1"]!, fields: NodeFields(flags: [Node.flagNoSuggest]))], author: .man, now: t)
        XCTAssertThrowsError(try s.apply([.setStatus(id["n1"]!, .done)], author: .model, now: t))
        XCTAssertThrowsError(try s.apply([.updateNode(id: id["n1"]!, fields: NodeFields(flags: []))], author: .model, now: t))
        XCTAssertThrowsError(try s.apply([.add("x", under: id["n1"]!)], author: .model, now: t))
        XCTAssertNoThrow(try s.apply([.updateNode(id: id["n2"]!, fields: NodeFields(aiNote: "remember"))], author: .model, now: t))
        XCTAssertThrowsError(try s.apply([.setNode(s.nodes[id["n2"]!]!)], author: .model, now: t))
        var many = Settings.default; many.maxOpsPerPatch = 2; s.settings = many
        XCTAssertThrowsError(try s.apply([.setStatus(id["n2"]!, .done), .setStatus(id["n3"]!, .done), .setStatus(id["n4"]!, .done)], author: .man, now: t))
    }

    func testAtomicity() throws {
        var (s, id) = Fixtures.starting()
        let before = s
        XCTAssertThrowsError(try s.apply([.setStatus(id["n1"]!, .done), .setStatus("nope", .done)], author: .man, now: t))
        XCTAssertEqual(s, before)
    }

    func testUndoIsExact() throws {
        var (s, id) = Fixtures.starting()
        let before = s.nodes
        try s.apply([.add("new", under: id["n1"]!, tmp: "a"), .add("deeper", under: Op.tmp("a"), tmp: "b"),
                     .setStatus(id["n2"]!, .doing), .crossOut(id: id["n3"]!)], author: .man, now: t)
        XCTAssertEqual(s.nodes.count, 7)
        try s.undoLast(now: t)
        XCTAssertEqual(s.nodes, before)
        XCTAssertEqual(s.patchLog.count, 6)   // 4 fixtures + patch + undo; the log only grows
        XCTAssertEqual(s.version, 6)
    }

    func testStaleBase() throws {
        var (s, id) = Fixtures.starting()
        XCTAssertThrowsError(try s.apply([.setStatus(id["n1"]!, .done)], author: .man, now: t, base: 0))
        XCTAssertNoThrow(try s.apply([.setStatus(id["n1"]!, .done)], author: .man, now: t, base: s.version))
    }

    func testStatusChangesAreLogged() throws {
        var (s, id) = Fixtures.starting()
        let r = try s.apply([.setStatus(id["n1"]!, .doing), .setStatus(id["n2"]!, .next), .setStatus(id["n1"]!, .done)], author: .man, now: t)
        XCTAssertEqual(r.entry.changes, [StatusChange(id: id["n1"]!, from: .open, to: .done),
                                         StatusChange(id: id["n2"]!, from: .open, to: .next)].sorted { $0.id < $1.id })
        XCTAssertEqual(Metrics.x(in: s, from: t, to: t), 1)
    }

    func testRoundTripCodable() throws {
        var (s, id) = Fixtures.starting()
        try s.apply([.setStatus(id["n1"]!, .doing), .add("c", under: id["n1"]!)], author: .man, now: t)
        s.session = Session(id: "s", startedAt: t, config: .default)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Store.self, from: data)
        XCTAssertEqual(back, s)
    }
}
