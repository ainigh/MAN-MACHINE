import XCTest
@testable import MpmCore

final class TidyTreeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A seeded random tree of `n` nodes with titles of varying length.
    func randomStore(_ n: Int, seed: UInt64) throws -> Store {
        var rng = SplitMix(seed)
        var s = Store(rootTitle: "root", now: t0, rootID: "root")
        s.settings.maxNewNodesPerPatch = .max; s.settings.maxOpsPerPatch = .max
        var ids = ["root"]
        for i in 0..<n {
            let parent = ids[Int(rng.next() % UInt64(ids.count))]
            let title = String(repeating: "x", count: 1 + Int(rng.next() % 30))
            let r = try s.apply([.add(title, under: parent, tmp: "t")], author: .man, now: t0.addingTimeInterval(Double(i)))
            ids.append(r.entry.assignedIDs["t"]!)
        }
        return s
    }

    func width(_ n: Node) -> Double { 24 + 7 * Double(min(n.title.count, 28)) }

    func testDeterministic() throws {
        let s = try randomStore(120, seed: 7)
        XCTAssertEqual(TidyTree.layout(s, width: width), TidyTree.layout(s, width: width))
        let decoded = try JSONDecoder().decode(Store.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(TidyTree.layout(decoded, width: width), TidyTree.layout(s, width: width))
    }

    func testNoOverlapsFor200Nodes() throws {
        for seed in [1, 2, 3, 42] as [UInt64] {
            let s = try randomStore(200, seed: seed)
            let pos = TidyTree.layout(s, width: width)
            XCTAssertEqual(pos.count, s.nodes.count)
            let byLevel = Dictionary(grouping: s.nodes.values) { pos[$0.id]!.y }
            for (_, level) in byLevel {
                let spans = level.map { (pos[$0.id]!.x - width($0) / 2, pos[$0.id]!.x + width($0) / 2) }.sorted { $0.0 < $1.0 }
                for (a, b) in zip(spans, spans.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(b.0 - a.1, 16 - 1e-6, "overlap at seed \(seed)")
                }
            }
        }
    }

    func testSiblingsOrderedByCreatedAtAndParentsCentred() throws {
        let s = try randomStore(80, seed: 9)
        let pos = TidyTree.layout(s, width: width)
        for n in s.nodes.values {
            let kids = s.children(of: n.id)
            guard !kids.isEmpty else { continue }
            let xs = kids.map { pos[$0.id]!.x }
            XCTAssertEqual(xs, xs.sorted(), "siblings out of createdAt order")
            XCTAssertEqual(pos[n.id]!.x, (xs.first! + xs.last!) / 2, accuracy: 1e-9)
            for k in kids { XCTAssertEqual(pos[k.id]!.y, pos[n.id]!.y + 64) }
        }
    }

    func testCollapsedSubtreesAreLeaves() throws {
        let s = try randomStore(60, seed: 5)
        let parent = s.nodes.values.first { !s.children(of: $0.id).isEmpty && $0.id != s.rootID }!
        let pos = TidyTree.layout(s, width: width, collapsed: [parent.id])
        for k in s.children(of: parent.id) { XCTAssertNil(pos[k.id]) }
        XCTAssertNotNil(pos[parent.id])
    }

    func testWalkerSpreadsSmallSubtreesBetweenWideOnes() {
        // a: wide deep subtree; b, c: leaves; d: wide deep subtree that collides with a below.
        let kids: [String: [String]] = ["r": ["a", "b", "c", "d"], "a": ["a1", "a2", "a3"], "d": ["d1", "d2", "d3"]]
        let pos = TidyTree.layout(root: "r", children: { kids[$0] ?? [] }, width: { _ in 40 })
        let gaps = [pos["b"]!.x - pos["a"]!.x, pos["c"]!.x - pos["b"]!.x, pos["d"]!.x - pos["c"]!.x]
        XCTAssertEqual(gaps[0], gaps[1], accuracy: 1e-9)
        XCTAssertEqual(gaps[1], gaps[2], accuracy: 1e-9)
    }

    func test150NodesLayOutWithinAFrame() throws {
        let s = try randomStore(150, seed: 11)
        let start = Date()
        for _ in 0..<10 { _ = TidyTree.layout(s, width: width) }
        let perLayout = Date().timeIntervalSince(start) / 10
        XCTAssertLessThan(perLayout, 0.016, "layout took \(perLayout * 1000) ms")
    }
}

struct SplitMix {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
