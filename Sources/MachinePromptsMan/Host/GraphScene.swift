import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGRect/CGPoint members live here on Apple platforms
#endif
import MpmCore

/// The graph as geometry (DESIGN §8): pills, parent edges, dependency arcs, proposal ghosts. Pure, so
/// the same store always draws the same picture (tasks/05), and testable without a screen. The view
/// only strokes and fills what is here.
public struct GraphScene: Equatable, Sendable {

    public struct Metrics: Equatable, Sendable {
        public var pillHeight: Double = 28
        public var padding: Double = 12
        public var dot: Double = 8
        public var dotGap: Double = 8
        public var lock: Double = 10
        public var lockGap: Double = 4
        public var gap: Double = 16
        public var levelHeight: Double = 64
        public var maxTitle: Int = 28
        public init() {}
    }

    public struct Box: Equatable, Sendable, Identifiable {
        public var id: NodeID
        public var center: CGPoint
        public var size: CGSize
        public var label: String
        public var title: String
        public var status: Status
        public var locked: Bool
        public var pinned: Bool
        /// Number of hidden descendants when the subtree is collapsed (DESIGN §8).
        public var collapsedCount: Int?
        public var updatedAt: Date
        public var rect: CGRect { CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height) }
        public var dotCenter: CGPoint { CGPoint(x: rect.minX + 12 + 4, y: center.y) }
    }

    public struct Ghost: Equatable, Sendable, Identifiable {
        public var id: String           // "ghost:<proposal>:<tmp>"
        public var proposalID: String
        public var parent: NodeID
        public var center: CGPoint
        public var size: CGSize
        public var label: String
    }

    public struct Curve: Equatable, Sendable {
        public var from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint
    }

    public struct Edge: Equatable, Sendable { public var parent: String; public var child: String; public var curve: Curve }
    public struct DepArc: Equatable, Sendable { public var node: NodeID; public var dep: NodeID; public var curve: Curve }
    public struct ProposedStatus: Equatable, Sendable { public var node: NodeID; public var status: Status; public var proposalID: String }
    public struct ProposedMove: Equatable, Sendable { public var node: NodeID; public var parent: NodeID; public var proposalID: String; public var curve: Curve }

    public var boxes: [Box] = []
    public var ghosts: [Ghost] = []
    public var edges: [Edge] = []
    public var deps: [DepArc] = []
    public var proposedStatus: [ProposedStatus] = []
    public var proposedMoves: [ProposedMove] = []
    public var bounds: CGRect = .zero

    public init() {}

    public func box(_ id: NodeID) -> Box? { boxes.first { $0.id == id } }

    /// DESIGN §2: single line, truncated with an ellipsis at 28 characters.
    public static func label(_ title: String, max: Int = 28) -> String {
        title.count <= max ? title : String(title.prefix(max - 1)) + "…"
    }

    /// Hidden subtrees: finished nodes with children whose parent is not finished (DESIGN §8).
    public static func collapsibleRoots(_ store: Store) -> Set<NodeID> {
        Set(store.nodes.values.filter { n in
            n.status.isFinished && !store.children(of: n.id).isEmpty
                && !(n.parent.flatMap { store.nodes[$0]?.status.isFinished } ?? false)
        }.map(\.id))
    }

    /// `textWidth` measures a label in the node font; the platform supplies it.
    public static func make(_ store: Store, collapsed: Set<NodeID> = [], metrics m: Metrics = Metrics(),
                            textWidth: (String) -> Double) -> GraphScene {
        // Ghost children from pending add_node ops join the layout so they get a real place.
        var ghostKids: [NodeID: [String]] = [:]
        var ghostInfo: [String: (proposal: String, parent: NodeID, title: String)] = [:]
        for p in store.pending {
            var tmpToGhost: [String: String] = [:]
            for case .addNode(let tmp, let parent, let title, _, _, _, _) in p.ops {
                let gid = "ghost:\(p.id):\(tmp)"
                tmpToGhost[tmp] = gid
                let realParent = parent.hasPrefix("tmp:") ? (tmpToGhost[String(parent.dropFirst(4))] ?? store.rootID) : parent
                guard store.nodes[realParent] != nil || ghostInfo[realParent] != nil else { continue }
                ghostKids[realParent, default: []].append(gid)
                ghostInfo[gid] = (p.id, realParent, title)
            }
        }

        func width(_ id: String) -> Double {
            if let n = store.nodes[id] {
                let lockW = n.noSuggest ? m.lock + m.lockGap : 0
                return m.padding + m.dot + m.dotGap + lockW + textWidth(label(n.title, max: m.maxTitle)) + m.padding
            }
            let t = ghostInfo[id]?.title ?? ""
            return m.padding + m.dot + m.dotGap + textWidth(label(t, max: m.maxTitle)) + m.padding
        }
        let pos = TidyTree.layout(root: store.rootID, children: { id in
            (collapsed.contains(id) ? [] : store.children(of: id).map(\.id)) + (ghostKids[id] ?? [])
        }, width: width, options: .init(gap: m.gap, levelHeight: m.levelHeight))

        var scene = GraphScene()
        func size(_ id: String) -> CGSize { CGSize(width: width(id), height: m.pillHeight) }
        func point(_ p: LayoutPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

        // Boxes in tree order, so drawing order is stable.
        var order: [NodeID] = []
        var stack = [store.rootID]
        while let id = stack.popLast() {
            order.append(id)
            guard !collapsed.contains(id) else { continue }
            stack.append(contentsOf: store.children(of: id).map(\.id).reversed())
        }
        for id in order {
            guard let n = store.nodes[id], let p = pos[id] else { continue }
            scene.boxes.append(Box(id: id, center: point(p), size: size(id), label: label(n.title, max: m.maxTitle),
                                   title: n.title, status: n.status, locked: n.noSuggest, pinned: n.pinned,
                                   collapsedCount: collapsed.contains(id) ? descendants(id, store) : nil,
                                   updatedAt: n.updatedAt))
            if let parent = n.parent, let pp = pos[parent] {
                scene.edges.append(Edge(parent: parent, child: id, curve: treeCurve(point(pp), point(p), m)))
            }
        }
        for (gid, info) in ghostInfo.sorted(by: { $0.key < $1.key }) {
            guard let p = pos[gid] else { continue }
            scene.ghosts.append(Ghost(id: gid, proposalID: info.proposal, parent: info.parent, center: point(p),
                                      size: size(gid), label: label(info.title, max: m.maxTitle)))
            if let pp = pos[info.parent] {
                scene.edges.append(Edge(parent: info.parent, child: gid, curve: treeCurve(point(pp), point(p), m)))
            }
        }
        // Dependency arcs, from the dependency into the node that waits for it.
        for b in scene.boxes {
            for d in store.nodes[b.id]?.deps ?? [] {
                guard let db = scene.box(d) else { continue }
                scene.deps.append(DepArc(node: b.id, dep: d, curve: arc(db.center, b.center, m)))
            }
        }
        // Proposed status changes and moves on existing nodes.
        for p in store.pending {
            for op in p.ops {
                switch op {
                case .updateNode(let id, let f):
                    if let s = f.status, scene.box(id) != nil { scene.proposedStatus.append(ProposedStatus(node: id, status: s, proposalID: p.id)) }
                case .crossOut(let id):
                    if scene.box(id) != nil { scene.proposedStatus.append(ProposedStatus(node: id, status: .crossedOut, proposalID: p.id)) }
                case .moveNode(let id, let parent):
                    if let b = scene.box(id), let pb = scene.box(parent) {
                        scene.proposedMoves.append(ProposedMove(node: id, parent: parent, proposalID: p.id,
                                                                curve: treeCurve(pb.center, b.center, m)))
                    }
                default: break
                }
            }
        }
        let rects = scene.boxes.map(\.rect) + scene.ghosts.map { CGRect(x: $0.center.x - $0.size.width / 2, y: $0.center.y - $0.size.height / 2, width: $0.size.width, height: $0.size.height) }
        scene.bounds = rects.reduce(rects.first ?? .zero) { $0.union($1) }
        return scene
    }

    static func descendants(_ id: NodeID, _ store: Store) -> Int {
        store.children(of: id).reduce(0) { $0 + 1 + descendants($1.id, store) }
    }

    static func treeCurve(_ parent: CGPoint, _ child: CGPoint, _ m: Metrics) -> Curve {
        let from = CGPoint(x: parent.x, y: parent.y + m.pillHeight / 2)
        let to = CGPoint(x: child.x, y: child.y - m.pillHeight / 2)
        let midY = (from.y + to.y) / 2
        return Curve(from: from, c1: CGPoint(x: from.x, y: midY), c2: CGPoint(x: to.x, y: midY), to: to)
    }

    /// A gentle bow to the side, so arcs do not lie on top of tree edges.
    static func arc(_ a: CGPoint, _ b: CGPoint, _ m: Metrics) -> Curve {
        let dx: Double = Double(b.x - a.x), dy: Double = Double(b.y - a.y)
        let len: Double = max(1, (dx * dx + dy * dy).squareRoot())
        let bow: Double = min(48, len / 4)
        let nx: Double = -dy / len * bow, ny: Double = dx / len * bow
        return Curve(from: a, c1: CGPoint(x: a.x + dx / 3 + nx, y: a.y + dy / 3 + ny),
                     c2: CGPoint(x: a.x + 2 * dx / 3 + nx, y: a.y + 2 * dy / 3 + ny), to: b)
    }

    // MARK: Hit testing (scene coordinates)

    public func hit(_ p: CGPoint) -> NodeID? {
        boxes.last { $0.rect.contains(p) }?.id
    }

    /// The status dot, a little larger than drawn, for D / N picking (DESIGN §8).
    public func dotHit(_ p: CGPoint) -> NodeID? {
        boxes.last { b in
            let c = b.dotCenter
            let dx: Double = Double(p.x - c.x), dy: Double = Double(p.y - c.y)
            return dx * dx + dy * dy <= 100
        }?.id
    }

    public func ghostHit(_ p: CGPoint) -> Ghost? {
        ghosts.last { g in
            abs(p.x - g.center.x) <= g.size.width / 2 && abs(p.y - g.center.y) <= g.size.height / 2
        }
    }

    /// Scale and offset that fit `bounds` into `viewport` with `margin`, never enlarging past 1.
    public static func fit(_ bounds: CGRect, in viewport: CGSize, margin: Double = 32) -> (scale: Double, offset: CGPoint) {
        guard bounds.width > 0, viewport.width > 0, viewport.height > 0 else { return (1, .zero) }
        let sx = (viewport.width - 2 * margin) / bounds.width
        let sy = (viewport.height - 2 * margin) / max(bounds.height, 1)
        let s = max(0.2, min(1, min(sx, sy)))
        let off = CGPoint(x: viewport.width / 2 - bounds.midX * s, y: viewport.height / 2 - bounds.midY * s)
        return (s, off)
    }
}

/// Rows for the grid (DESIGN §9): tree order, with depth for indentation.
public enum TreeOrder {
    public static func rows(_ store: Store) -> [(node: Node, depth: Int)] {
        var out: [(Node, Int)] = []
        func walk(_ id: NodeID, _ d: Int) {
            guard let n = store.nodes[id] else { return }
            out.append((n, d))
            for c in store.children(of: id) { walk(c.id, d + 1) }
        }
        walk(store.rootID, 0)
        return out
    }
}
