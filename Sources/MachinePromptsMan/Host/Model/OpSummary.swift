import Foundation
import MpmCore

/// One-line descriptions of ops, derived from the ops and the store, never from the model's words
/// (SPEC §8.5). Used for declined memory, which the model sees, and for proposal rows.
public enum OpSummary {
    /// Replaces `tmp:` references with the ids an earlier patch assigned. A tmp id resolves only within
    /// its own patch (SPEC §5.1), so ops left over from a partly accepted proposal need this to apply.
    public static func resolving(_ op: Op, _ assigned: [String: NodeID]) -> Op {
        func r(_ id: NodeID) -> NodeID {
            id.hasPrefix("tmp:") ? assigned[String(id.dropFirst(4))] ?? id : id
        }
        switch op {
        case .addNode(let t, let p, let title, let s, let due, let progress, let d):
            return .addNode(tmpID: t, parent: r(p), title: title, status: s, due: due, progress: progress, description: d)
        case .updateNode(let id, let f): return .updateNode(id: r(id), fields: f)
        case .moveNode(let id, let p): return .moveNode(id: r(id), parent: r(p))
        case .crossOut(let id): return .crossOut(id: r(id))
        case .restore(let id): return .restore(id: r(id))
        case .removeNode(let id): return .removeNode(id: r(id))
        case .addDep(let id, let d): return .addDep(id: r(id), dep: r(d))
        case .removeDep(let id, let d): return .removeDep(id: r(id), dep: r(d))
        case .setNode: return op
        }
    }

    public static func describe(_ op: Op, in store: Store, tmpTitles: [String: String] = [:]) -> String {
        func t(_ id: NodeID) -> String {
            if id.hasPrefix("tmp:") { return "“\(tmpTitles[String(id.dropFirst(4))] ?? id)”" }
            return store.nodes[id].map { "“\($0.title)”" } ?? id
        }
        switch op {
        case .addNode(_, let parent, let title, let status, _, _, _):
            return "add “\(title)” under \(t(parent))" + (status.map { " as \($0.rawValue)" } ?? "")
        case .updateNode(let id, let f):
            var parts: [String] = []
            if let s = f.status { parts.append("status \(store.nodes[id]?.status.rawValue ?? "?") → \(s.rawValue)") }
            if let title = f.title { parts.append("rename to “\(title)”") }
            if let p = f.progress { parts.append("progress \(p)%") }
            if f.clearDue { parts.append("clear due") } else if let d = f.due { parts.append("due \(day(d))") }
            if f.description != nil { parts.append("description") }
            if f.links != nil { parts.append("links") }
            if f.aiNote != nil { parts.append("note") }
            if let flags = f.flags { parts.append("flags [\(flags.sorted().joined(separator: ", "))]") }
            return "\(t(id)): " + (parts.isEmpty ? "no change" : parts.joined(separator: ", "))
        case .moveNode(let id, let p): return "move \(t(id)) under \(t(p))"
        case .crossOut(let id): return "cross out \(t(id))"
        case .restore(let id): return "restore \(t(id))"
        case .removeNode(let id): return "remove \(t(id))"
        case .addDep(let id, let d): return "\(t(id)) waits for \(t(d))"
        case .removeDep(let id, let d): return "\(t(id)) no longer waits for \(t(d))"
        case .setNode(let n): return "set “\(n.title)”"
        }
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    public static func describe(_ ops: [Op], in store: Store) -> String {
        var tmp: [String: String] = [:]
        for case .addNode(let tid, _, let title, _, _, _, _) in ops { tmp[tid] = title }
        return ops.map { describe($0, in: store, tmpTitles: tmp) }.joined(separator: "; ")
    }

    /// Existing node ids an op touches (not the ones it creates).
    public static func existingIDs(_ ops: [Op], in store: Store) -> [NodeID] {
        var seen = Set<NodeID>(); var out: [NodeID] = []
        for id in ops.flatMap(\.touchedIDs) where store.nodes[id] != nil && seen.insert(id).inserted { out.append(id) }
        return out
    }
}
