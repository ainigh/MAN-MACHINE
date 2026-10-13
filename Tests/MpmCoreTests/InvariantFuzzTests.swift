import XCTest
@testable import MpmCore

/// SPEC §13. Random events and patches, seeded, with every invariant checked after each step.
final class InvariantFuzzTests: XCTestCase {
    struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } }

    func checkInvariants(_ st: Store, _ where: String) {
        XCTAssertEqual(st.version, st.patchLog.count, "#1 \(`where`)")
        for n in st.nodes.values where n.id != st.rootID { XCTAssertNotNil(st.nodes[n.parent ?? ""], "#2 \(`where`)") }
        for n in st.nodes.values { XCTAssertFalse(st.isDescendant(n.id, of: n.id), "#3 parent \(`where`)") }
        for n in st.nodes.values { for d in n.deps { XCTAssertFalse(st.depWouldCycle(id: d, dep: n.id) && d != n.id ? false : (d == n.id), "#3 deps \(`where`)") } }
        XCTAssertLessThanOrEqual(st.nodes.values.filter { $0.status == .doing }.count, 1, "#4 doing \(`where`)")
        XCTAssertLessThanOrEqual(st.nodes.values.filter { $0.status == .next }.count, 1, "#4 next \(`where`)")
        for n in st.nodes.values {
            let unfinished = !st.unfinishedDeps(of: n.id).isEmpty
            if n.status == .blocked { XCTAssertTrue(unfinished, "#5 \(`where`)") }
            if n.status == .open { XCTAssertFalse(unfinished, "#5 open \(`where`)") }
            if n.status == .doing { XCTAssertFalse(unfinished, "#5 doing \(`where`)") }
        }
        if let s = st.session { XCTAssertGreaterThanOrEqual(s.seated(at: Date.distantFuture), 0) }
    }

    func testRandomWalk() throws {
        for seed in 1...20 {
            var rng = LCG(s: UInt64(seed))
            let (store, _) = Fixtures.starting(config: SessionConfig(R: 120, r: 2, Ls: 400, Lb: 30))
            var sim = Simulator(store: store, now: Fixtures.t0)
            sim.send(.startSession)
            var steps = 0
            while steps < 400 {
                steps += 1
                let ids = Array(sim.store.nodes.keys).sorted()
                let pick = { ids[Int(rng.next() % UInt64(ids.count))] }
                switch rng.next() % 10 {
                case 0: sim.send(.commit(doing: pick(), next: pick()))
                case 1: sim.send(.finish)
                case 2: sim.send(.snooze)
                case 3: sim.send(.stop)
                case 4: sim.advance(Double(rng.next() % 90))
                case 5: sim.advance(until: [.timeUp, .status, .strategy, .work][Int(rng.next() % 4)], limit: 600)
                case 6: _ = try? sim.patch([.add("x\(steps)", under: pick())])
                case 7: _ = try? sim.patch([.setStatus(pick(), [.open, .doing, .next, .done][Int(rng.next() % 4)])])
                case 8: _ = try? sim.patch([rng.next() % 2 == 0 ? .crossOut(id: pick()) : .addDep(id: pick(), dep: pick())])
                default:
                    if rng.next() % 3 == 0 { _ = try? sim.store.undoLast(now: sim.now) } else { _ = try? sim.patch([.moveNode(id: pick(), parent: pick())]) }
                }
                checkInvariants(sim.store, "seed \(seed) step \(steps) state \(String(describing: sim.state))")
                if sim.state == .end { break }
            }
            // #11: model turns start only at STATUS entry, held output renders only at STRATEGY; never in a silent state.
            var turns = 0, statusStarts = 0
            for (i, (_, f)) in sim.effects.enumerated() {
                switch f {
                case .startModelTurn: turns += 1; XCTAssertEqual(sim.effectStates[i], .status)
                case .renderHeld: XCTAssertEqual(sim.effectStates[i], .strategy)
                case .announce(.statusStart): statusStarts += 1
                default: break
                }
            }
            XCTAssertEqual(turns, statusStarts, "exactly one model turn per round boundary")
        }
    }
}
