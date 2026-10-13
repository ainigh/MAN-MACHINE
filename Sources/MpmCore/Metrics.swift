import Foundation

public struct DiffLine: Equatable, Sendable, Codable {
    public var id: NodeID
    public var title: String
    public var from: Status
    public var to: Status
}

public enum Metrics {
    /// SPEC §6.6.1. Distinct nodes that changed to `done` in [from, to] and are still done now.
    /// Closed at `to` because x is frozen at the instant STATUS is entered, and a patch and the `finish`
    /// that follows it may share a timestamp.
    public static func x(in store: Store, from: Date, to: Date) -> Int {
        var ids = Set<NodeID>()
        for e in store.patchLog where e.at >= from && e.at <= to {
            for c in e.changes where c.to == .done { ids.insert(c.id) }
        }
        return ids.filter { store.nodes[$0]?.status == .done }.count
    }

    /// Net status change per node over [from, to): first `from`, last `to`. Nodes with no net change are omitted.
    public static func roundDiff(in store: Store, from: Date, to: Date) -> [DiffLine] {
        var first: [NodeID: Status] = [:]
        var last: [NodeID: Status] = [:]
        var order: [NodeID] = []
        for e in store.patchLog where e.at >= from && e.at <= to {
            for c in e.changes {
                if first[c.id] == nil { first[c.id] = c.from; order.append(c.id) }
                last[c.id] = c.to
            }
        }
        return order.compactMap { id in
            guard let f = first[id], let l = last[id], f != l else { return nil }
            return DiffLine(id: id, title: store.nodes[id]?.title ?? id, from: f, to: l)
        }
    }
}
