import XCTest
import MpmCore
@testable import MpmHost

final class GraphSceneTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func w(_ s: String) -> Double { Double(s.count) * 7 }

    func store() throws -> (Store, [String: NodeID]) {
        var s = Store(rootTitle: "Launch v2", now: t0, rootID: "root")
        var ids: [String: NodeID] = [:]
        for (i, (name, parent)) in [("spec", "root"), ("api", "root"), ("review", "root"), ("deploy", "api"),
                                    ("a very long title that goes on and on", "root")].enumerated() {
            let r = try s.apply([.add(name, under: ids[parent] ?? parent, tmp: "x")], author: .man, now: t0.addingTimeInterval(Double(i)))
            ids[name] = r.entry.assignedIDs["x"]!
        }
        return (s, ids)
    }

    func testDeterministicAndTruncated() throws {
        let (s, _) = try store()
        XCTAssertEqual(GraphScene.make(s, textWidth: w), GraphScene.make(s, textWidth: w))
        let long = GraphScene.make(s, textWidth: w).boxes.first { $0.title.hasPrefix("a very") }!
        XCTAssertEqual(long.label.count, 28)
        XCTAssertTrue(long.label.hasSuffix("…"))
        XCTAssertEqual(GraphScene.label("short"), "short")
    }

    func testEdgesDepsAndHits() throws {
        var (s, id) = try store()
        try s.apply([.addDep(id: id["review"]!, dep: id["spec"]!)], author: .man, now: t0.addingTimeInterval(10))
        let scene = GraphScene.make(s, textWidth: w)
        XCTAssertEqual(scene.edges.count, 5)
        XCTAssertEqual(scene.deps.map(\.node), [id["review"]!])
        let api = scene.box(id["api"]!)!
        XCTAssertEqual(scene.hit(api.center), id["api"])
        XCTAssertEqual(scene.dotHit(api.dotCenter), id["api"])
        XCTAssertNil(scene.hit(CGPoint(x: -10_000, y: -10_000)))
        XCTAssertTrue(scene.bounds.contains(api.rect))
    }

    func testCollapsedFinishedSubtree() throws {
        var (s, id) = try store()
        try s.apply([.setStatus(id["deploy"]!, .done), .setStatus(id["api"]!, .done)], author: .man, now: t0.addingTimeInterval(10))
        XCTAssertEqual(GraphScene.collapsibleRoots(s), [id["api"]!])
        let scene = GraphScene.make(s, collapsed: [id["api"]!], textWidth: w)
        XCTAssertNil(scene.box(id["deploy"]!))
        XCTAssertEqual(scene.box(id["api"]!)?.collapsedCount, 1)
    }

    func testProposalGhosts() throws {
        var (s, id) = try store()
        s.pending = [Proposal(id: "p1", turnID: "t", at: t0, ops: [
            .add("write tests", under: id["api"]!, tmp: "t1"),
            .add("unit", under: Op.tmp("t1"), tmp: "t2"),
            .setStatus(id["spec"]!, .done),
            .moveNode(id: id["review"]!, parent: id["api"]!),
        ], say: "Split the API work.")]
        let scene = GraphScene.make(s, textWidth: w)
        XCTAssertEqual(scene.ghosts.map(\.id).sorted(), ["ghost:p1:t1", "ghost:p1:t2"])
        XCTAssertEqual(scene.ghosts.first { $0.id == "ghost:p1:t2" }?.parent, "ghost:p1:t1")
        XCTAssertEqual(scene.proposedStatus, [GraphScene.ProposedStatus(node: id["spec"]!, status: .done, proposalID: "p1")])
        XCTAssertEqual(scene.proposedMoves.map(\.node), [id["review"]!])
        XCTAssertEqual(scene.ghostHit(scene.ghosts[0].center)?.proposalID, "p1")
        // No ghost overlaps a real pill on its level.
        for g in scene.ghosts {
            for b in scene.boxes where abs(b.center.y - g.center.y) < 1 {
                XCTAssertGreaterThanOrEqual(abs(b.center.x - g.center.x), (b.size.width + g.size.width) / 2)
            }
        }
    }

    func testFitNeverEnlargesAndCentres() {
        let (s1, o1) = GraphScene.fit(CGRect(x: 0, y: 0, width: 100, height: 50), in: CGSize(width: 800, height: 600))
        XCTAssertEqual(s1, 1)
        XCTAssertEqual(o1, CGPoint(x: 350, y: 275))
        let (s2, _) = GraphScene.fit(CGRect(x: 0, y: 0, width: 4000, height: 300), in: CGSize(width: 800, height: 600))
        XCTAssertLessThan(s2, 1)
    }

    func testTreeOrderRows() throws {
        let (s, id) = try store()
        let rows = TreeOrder.rows(s)
        XCTAssertEqual(rows.map(\.node.title), ["Launch v2", "spec", "api", "deploy", "review", "a very long title that goes on and on"])
        XCTAssertEqual(rows.first { $0.node.id == id["deploy"] }?.depth, 2)
    }
}

final class LayoutTweenTests: XCTestCase {
    func testSpringStartsAtZeroSettlesAtOneWithSmallOvershoot() {
        XCTAssertEqual(Spring.progress(0), 0)
        XCTAssertEqual(Spring.progress(5), 1)
        let samples = stride(from: 0.0, through: 1.0, by: 0.01).map { Spring.progress($0) }
        XCTAssertLessThan(samples.max()!, 1.02)                 // damping 0.85: barely any overshoot
        XCTAssertEqual(Spring.progress(0.99), 1, accuracy: 0.01)
    }

    func testRetargetStartsNewNodesAtTheirParent() {
        var t = LayoutTween()
        let t0 = Date(timeIntervalSince1970: 0)
        t.retarget(["a": CGPoint(x: 0, y: 0)], parents: [:], now: t0, instant: false)
        XCTAssertEqual(t.position("a", at: t0), CGPoint(x: 0, y: 0))
        t.retarget(["a": CGPoint(x: 100, y: 0), "b": CGPoint(x: 100, y: 64)], parents: ["b": "a"], now: t0.addingTimeInterval(2), instant: false)
        XCTAssertEqual(t.position("b", at: t0.addingTimeInterval(2)), CGPoint(x: 0, y: 0))     // from a's current place
        XCTAssertEqual(t.position("b", at: t0.addingTimeInterval(4)), CGPoint(x: 100, y: 64))
        XCTAssertTrue(t.animating(at: t0.addingTimeInterval(2.5)))
        t.retarget(["a": CGPoint(x: 5, y: 5)], parents: [:], now: t0.addingTimeInterval(9), instant: true)
        XCTAssertEqual(t.position("a", at: t0.addingTimeInterval(9)), CGPoint(x: 5, y: 5))
    }
}
