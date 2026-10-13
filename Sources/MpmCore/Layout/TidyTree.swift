import Foundation

public struct LayoutPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A tidy top-down tree layout in the Reingold–Tilford / Walker family, for variable node widths
/// (DESIGN §8). Children are packed left to right against the contour of their elder siblings at every
/// depth; when a subtree is pushed right by a sibling further left than its neighbour, the space is
/// shared out among the siblings in between (Walker's spacing), and each parent is centred over its
/// first and last child. Deterministic: the same input always gives the same picture. Pure.
public enum TidyTree {

    public struct Options: Equatable, Sendable {
        /// Minimum horizontal space between any two nodes on the same level.
        public var gap: Double
        /// Distance between the centres of successive levels.
        public var levelHeight: Double
        public init(gap: Double = 16, levelHeight: Double = 64) { self.gap = gap; self.levelHeight = levelHeight }
    }

    /// Node centres. The root is at (0, 0); level k is at y = k · levelHeight.
    public static func layout<ID: Hashable>(root: ID, children: (ID) -> [ID], width: (ID) -> Double,
                                            options: Options = Options()) -> [ID: LayoutPoint] {
        var relX: [ID: Double] = [:]
        _ = place(root, children: children, width: width, gap: options.gap, relX: &relX)
        var out: [ID: LayoutPoint] = [root: LayoutPoint(x: 0, y: 0)]
        var stack: [(ID, Double, Int)] = [(root, 0, 0)]
        while let (id, x, depth) = stack.popLast() {
            for c in children(id) {
                let cx = x + (relX[c] ?? 0)
                out[c] = LayoutPoint(x: cx, y: Double(depth + 1) * options.levelHeight)
                stack.append((c, cx, depth + 1))
            }
        }
        return out
    }

    /// Lays out the store's tree. `collapsed` nodes are drawn as leaves (DESIGN §8 view state, never store state).
    public static func layout(_ store: Store, width: (Node) -> Double, collapsed: Set<NodeID> = [],
                              options: Options = Options()) -> [NodeID: LayoutPoint] {
        layout(root: store.rootID,
               children: { collapsed.contains($0) ? [] : store.children(of: $0).map(\.id) },
               width: { store.nodes[$0].map(width) ?? 0 },
               options: options)
    }

    /// Left and right edges per depth, relative to the subtree root's centre.
    private struct Contour {
        var left: [Double]
        var right: [Double]
    }

    private static func place<ID: Hashable>(_ id: ID, children: (ID) -> [ID], width: (ID) -> Double, gap: Double,
                                            relX: inout [ID: Double]) -> Contour {
        let w = width(id)
        let kids = children(id)
        guard !kids.isEmpty else { return Contour(left: [-w / 2], right: [w / 2]) }

        let cs = kids.map { place($0, children: children, width: width, gap: gap, relX: &relX) }
        var off = [Double](repeating: 0, count: kids.count)

        func merged(upTo n: Int) -> (left: [Double], right: [Double], owner: [Int]) {
            var l: [Double] = [], r: [Double] = [], o: [Int] = []
            for i in 0..<n {
                for d in 0..<cs[i].left.count {
                    let cl = cs[i].left[d] + off[i], cr = cs[i].right[d] + off[i]
                    if d < l.count {
                        l[d] = min(l[d], cl)
                        if cr >= r[d] { r[d] = cr; o[d] = i }
                    } else {
                        l.append(cl); r.append(cr); o.append(i)
                    }
                }
            }
            return (l, r, o)
        }
        func separation(_ i: Int, against acc: (left: [Double], right: [Double], owner: [Int])) -> (shift: Double, culprit: Int) {
            var need = -Double.infinity, culprit = i - 1
            for d in 0..<min(acc.right.count, cs[i].left.count) {
                let s = acc.right[d] + gap - cs[i].left[d]
                if s > need { need = s; culprit = acc.owner[d] }
            }
            return (need, culprit)
        }

        for i in 1..<kids.count {
            let acc = merged(upTo: i)
            let (need, culprit) = separation(i, against: acc)
            off[i] = need
            // Walker: share the push among the siblings between the culprit and this one, if that stays clear.
            let adjacent = off[i - 1] + cs[i - 1].right[0] + gap - cs[i].left[0]
            if culprit < i - 1, need > adjacent {
                let spread = need - adjacent
                let saved = off
                for j in (culprit + 1)..<i { off[j] += spread * Double(j - culprit) / Double(i - culprit) }
                if !clear(cs, off, moved: (culprit + 1)..<i, upTo: i, gap: gap) { off = saved }
            }
        }

        let mid = (off[0] + off[kids.count - 1]) / 2
        for (i, k) in kids.enumerated() { relX[k] = off[i] - mid }
        let acc = merged(upTo: kids.count)
        return Contour(left: [-w / 2] + acc.left.map { $0 - mid }, right: [w / 2] + acc.right.map { $0 - mid })
    }

    /// After moving `moved` right, each of them is still at least `gap` from every sibling after it up to `upTo`.
    private static func clear(_ cs: [Contour], _ off: [Double], moved: Range<Int>, upTo last: Int, gap: Double) -> Bool {
        for j in moved {
            for k in (j + 1)...last {
                for d in 0..<min(cs[j].right.count, cs[k].left.count)
                where cs[j].right[d] + off[j] + gap > cs[k].left[d] + off[k] + 1e-9 {
                    return false
                }
            }
        }
        return true
    }
}
