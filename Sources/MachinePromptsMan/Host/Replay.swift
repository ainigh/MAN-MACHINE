import Foundation
import MpmCore

/// Rebuilds nodes from patch-log entries the snapshot does not yet contain (tasks/01).
///
/// Re-applying an entry's `ops` verbatim would not reproduce the store: `add_node` mints a fresh
/// ULID, and later entries refer to the id minted the first time. So each `add_node` becomes a
/// `set_node` carrying the id recorded in `assignedIDs`, and `tmp:` references are resolved the
/// same way. Everything else replays through `Store.apply` as `system`, at the entry's own time,
/// so `updatedAt`, slot displacement and `blocked` derivation come out as they did originally.
enum Replay {

    static func catchUp(_ store: inout Store, with entries: [LogEntry]) throws {
        let saved = (store.settings.maxOpsPerPatch, store.settings.maxNewNodesPerPatch)
        // Limits applied when the entry was first accepted; a later, lower limit must not reject history.
        store.settings.maxOpsPerPatch = .max
        store.settings.maxNewNodesPerPatch = .max
        defer { (store.settings.maxOpsPerPatch, store.settings.maxNewNodesPerPatch) = saved }

        for e in entries {
            let expected = store.patchLog.count + 1
            guard e.seq == expected else { throw PersistenceError.logGap(expected: expected, found: e.seq) }
            do {
                try store.apply(replayable(e), author: .system, now: e.at)
            } catch {
                throw PersistenceError.replayFailed(seq: e.seq, reason: "\(error)")
            }
            // Keep the original entry: author, turn and session attribution are history (SPEC §3.3, §13 #7).
            store.patchLog[store.patchLog.count - 1] = e
        }
    }

    static func replayable(_ e: LogEntry) -> [Op] {
        func r(_ id: NodeID) -> NodeID {
            id.hasPrefix("tmp:") ? (e.assignedIDs[String(id.dropFirst(4))] ?? id) : id
        }
        return e.ops.map { op in
            switch op {
            case .addNode(let tmp, let parent, let title, let status, let due, let progress, let description):
                let id = e.assignedIDs[tmp] ?? Op.tmp(tmp)
                return .setNode(Node(id: id, title: title, parent: r(parent), status: status ?? .open, due: due,
                                     progress: progress ?? 0, description: description ?? "",
                                     createdAt: e.at, updatedAt: e.at))
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
    }
}
