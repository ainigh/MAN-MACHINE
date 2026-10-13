import Foundation

public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case unknownNode(NodeID)
    case invalidParent(NodeID)
    case parentCycle(NodeID)
    case depCycle(NodeID, NodeID)
    case depOnSelf(NodeID)
    case cannotSetBlocked(NodeID)
    case openWithUnfinishedDeps(NodeID)
    case doingOnUnavailable(NodeID, Status)
    case nextOnUnavailable(NodeID, Status)
    case wouldBlockDoing(NodeID)
    case cannotRemove(NodeID, String)
    case cannotRestore(NodeID)
    case rootImmutable
    case locked(NodeID)
    case fieldNotMutable(NodeID, String)
    case systemOnly
    case tooManyOps(Int, limit: Int)
    case tooManyNewNodes(Int, limit: Int)
    case progressOutOfRange(Int)
    case patchesBlockedDuringBreak
    case stale(base: Int, version: Int)

    public var description: String {
        switch self {
        case .unknownNode(let id): return "unknown node \(id)"
        case .invalidParent(let id): return "invalid parent \(id)"
        case .parentCycle(let id): return "moving \(id) would create a parent cycle"
        case .depCycle(let a, let b): return "dependency \(a) → \(b) would create a cycle"
        case .depOnSelf(let id): return "\(id) cannot depend on itself"
        case .cannotSetBlocked(let id): return "blocked is derived; cannot set it on \(id)"
        case .openWithUnfinishedDeps(let id): return "\(id) has unfinished dependencies"
        case .doingOnUnavailable(let id, let s): return "cannot set doing on \(id) (\(s.rawValue))"
        case .nextOnUnavailable(let id, let s): return "cannot set next on \(id) (\(s.rawValue))"
        case .wouldBlockDoing(let id): return "that dependency would block the doing node \(id)"
        case .cannotRemove(let id, let why): return "cannot remove \(id): \(why)"
        case .cannotRestore(let id): return "\(id) is not crossed out"
        case .rootImmutable: return "the root cannot be moved, crossed out or removed"
        case .locked(let id): return "\(id) is locked (no_suggest)"
        case .fieldNotMutable(let id, let f): return "\(f) on \(id) is not mutable by this author"
        case .systemOnly: return "set_node is system-only"
        case .tooManyOps(let n, let l): return "\(n) ops exceeds the limit of \(l)"
        case .tooManyNewNodes(let n, let l): return "\(n) new nodes exceeds the limit of \(l)"
        case .progressOutOfRange(let p): return "progress \(p) is outside 0…100"
        case .patchesBlockedDuringBreak: return "not available during a movement break"
        case .stale(let b, let v): return "patch base \(b) is behind store version \(v)"
        }
    }
}

public struct ApplyResult: Equatable, Sendable {
    public var entry: LogEntry
    /// Nodes that became `open` because their deps were all cleared by this patch.
    public var unblocked: [NodeID]
}

/// SPEC §3.2
public struct Store: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 2
    public var version: Int = 0
    public var rootID: NodeID
    public var nodes: [NodeID: Node]
    public var patchLog: [LogEntry] = []
    public var session: Session?
    public var pending: [Proposal] = []
    public var question: PendingQuestion?
    public var held: [Envelope] = []
    public var declined: [Declined] = []
    public var settings: Settings
    public var schedule: [ScheduleEntry] = []

    public init(rootTitle: String = "Goal", now: Date, settings: Settings = .default, rootID: NodeID? = nil) {
        let rid = rootID ?? IDs.ulid(now: now)
        self.rootID = rid
        self.nodes = [rid: Node(id: rid, title: rootTitle, parent: nil, createdAt: now, updatedAt: now)]
        self.settings = settings
    }

    // MARK: Queries

    public var doing: Node? { nodes.values.first { $0.status == .doing } }
    public var next: Node? { nodes.values.first { $0.status == .next } }

    public func children(of id: NodeID) -> [Node] {
        nodes.values.filter { $0.parent == id }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func isDescendant(_ id: NodeID, of ancestor: NodeID) -> Bool {
        var cur = nodes[id]?.parent
        var guardCount = 0
        while let c = cur, guardCount < nodes.count + 1 {
            if c == ancestor { return true }
            cur = nodes[c]?.parent; guardCount += 1
        }
        return false
    }

    /// Nodes in `deps` that are not done.
    public func unfinishedDeps(of id: NodeID) -> [NodeID] {
        (nodes[id]?.deps ?? []).filter { nodes[$0]?.status != .done }
    }

    /// Would adding `dep` to `id` create a cycle in deps?
    func depWouldCycle(id: NodeID, dep: NodeID) -> Bool {
        var stack = [dep]; var seen = Set<NodeID>()
        while let cur = stack.popLast() {
            if cur == id { return true }
            if !seen.insert(cur).inserted { continue }
            stack.append(contentsOf: nodes[cur]?.deps ?? [])
        }
        return false
    }

    public var oldestOpen: Node? {
        nodes.values.filter { $0.status == .open && $0.id != rootID }
            .min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Has this node ever held a slot or been done, per the log? (SPEC §5.1 remove_node)
    public func everHeldSlotOrDone(_ id: NodeID) -> Bool {
        if let s = nodes[id]?.status, s == .doing || s == .next || s == .done { return true }
        return patchLog.contains { e in
            e.changes.contains { c in c.id == id && (c.to == .doing || c.to == .next || c.to == .done) }
        }
    }

    // MARK: Apply (SPEC §5.2–5.4)

    /// Validates and applies a patch as `author`. Throws without changing anything on any violation.
    @discardableResult
    public mutating func apply(_ ops: [Op], author: Author, now: Date, base: Int? = nil,
                               turnID: String? = nil) throws -> ApplyResult {
        if let base, base != version { throw ValidationError.stale(base: base, version: version) }
        if session?.state == .break && author != .system { throw ValidationError.patchesBlockedDuringBreak }
        if ops.count > settings.maxOpsPerPatch { throw ValidationError.tooManyOps(ops.count, limit: settings.maxOpsPerPatch) }
        let newCount = ops.filter { if case .addNode = $0 { return true } else { return false } }.count
        if newCount > settings.maxNewNodesPerPatch { throw ValidationError.tooManyNewNodes(newCount, limit: settings.maxNewNodesPerPatch) }

        // Work on a copy; commit only if every op is valid.
        var work = self
        var assigned: [String: NodeID] = [:]
        var touched = Set<NodeID>()
        var added = Set<NodeID>()
        var removed: [NodeID: Node] = [:]
        var restored = Set<NodeID>()       // set wholesale by `setNode`; keep their own updatedAt

        func resolve(_ id: NodeID) -> NodeID {
            if id.hasPrefix("tmp:"), let real = assigned[String(id.dropFirst(4))] { return real }
            return id
        }
        func node(_ id: NodeID) throws -> Node {
            guard let n = work.nodes[resolve(id)] else { throw ValidationError.unknownNode(id) }
            return n
        }
        func checkModelMayTouch(_ n: Node) throws {
            if author == .model && n.noSuggest { throw ValidationError.locked(n.id) }
        }
        func takeSlot(_ status: Status, for id: NodeID) {
            guard status == .doing || status == .next else { return }
            for (k, n) in work.nodes where n.status == status && k != id {
                work.nodes[k]!.status = .open; touched.insert(k)
            }
        }
        func setStatus(_ id: NodeID, _ s: Status) throws {
            let n = try node(id)
            switch s {
            case .blocked: throw ValidationError.cannotSetBlocked(id)
            case .open:
                if !work.unfinishedDeps(of: n.id).isEmpty { throw ValidationError.openWithUnfinishedDeps(id) }
            case .doing:
                if !n.status.isLive { throw ValidationError.doingOnUnavailable(id, n.status) }
                if !work.unfinishedDeps(of: n.id).isEmpty { throw ValidationError.openWithUnfinishedDeps(id) }
            case .next:
                if n.status.isFinished { throw ValidationError.nextOnUnavailable(id, n.status) }
                if n.status == .blocked {
                    let d = work.doing?.id
                    let unfinished = work.unfinishedDeps(of: n.id)
                    if !(unfinished.count == 1 && unfinished.first == d) { throw ValidationError.nextOnUnavailable(id, n.status) }
                }
            case .done, .crossedOut: break
            }
            takeSlot(s, for: n.id)
            work.nodes[n.id]!.status = s; touched.insert(n.id)
        }

        for op in ops {
            switch op {
            case .addNode(let tmp, let parent, let title, let status, let due, let progress, let description):
                let p = try node(parent)
                if author == .model { try checkModelMayTouch(p) }
                if let progress, !(0...100).contains(progress) { throw ValidationError.progressOutOfRange(progress) }
                let id = IDs.ulid(now: now)
                let n = Node(id: id, title: title, parent: p.id, status: .open, due: due, progress: progress ?? 0,
                             description: description ?? "", createdAt: now, updatedAt: now)
                work.nodes[id] = n; assigned[tmp] = id; added.insert(id); touched.insert(id)
                if let status { try setStatus(id, status) }

            case .updateNode(let rawID, let f):
                let n = try node(rawID); let id = n.id
                try checkModelMayTouch(n)
                if let t = f.title { work.nodes[id]!.title = t }
                if let p = f.progress {
                    if !(0...100).contains(p) { throw ValidationError.progressOutOfRange(p) }
                    work.nodes[id]!.progress = p
                }
                if let d = f.description { work.nodes[id]!.description = d }
                if let l = f.links { work.nodes[id]!.links = l }
                if let a = f.aiNote { work.nodes[id]!.aiNote = a }
                if f.clearDue { work.nodes[id]!.due = nil } else if let d = f.due { work.nodes[id]!.due = d }
                if let flags = f.flags {
                    if author == .model && n.flags.contains(Node.flagNoSuggest) && !flags.contains(Node.flagNoSuggest) {
                        throw ValidationError.fieldNotMutable(id, "flags.no_suggest")
                    }
                    work.nodes[id]!.flags = flags
                }
                touched.insert(id)
                if let s = f.status { try setStatus(id, s) }

            case .moveNode(let rawID, let rawParent):
                let n = try node(rawID); let p = try node(rawParent)
                if n.id == work.rootID { throw ValidationError.rootImmutable }
                try checkModelMayTouch(n)
                if p.id == n.id || work.isDescendant(p.id, of: n.id) { throw ValidationError.parentCycle(n.id) }
                work.nodes[n.id]!.parent = p.id; touched.insert(n.id)

            case .crossOut(let rawID):
                let n = try node(rawID)
                if n.id == work.rootID { throw ValidationError.rootImmutable }
                try checkModelMayTouch(n)
                var stack = [n.id]
                while let cur = stack.popLast() {
                    if let s = work.nodes[cur]?.status, !s.isFinished {
                        work.nodes[cur]!.status = .crossedOut; touched.insert(cur)
                    }
                    stack.append(contentsOf: work.children(of: cur).map(\.id))
                }

            case .restore(let rawID):
                let n = try node(rawID)
                try checkModelMayTouch(n)
                if n.status != .crossedOut { throw ValidationError.cannotRestore(n.id) }
                work.nodes[n.id]!.status = .open; touched.insert(n.id)

            case .removeNode(let rawID):
                let n = try node(rawID)
                if n.id == work.rootID { throw ValidationError.rootImmutable }
                if author == .model { throw ValidationError.cannotRemove(n.id, "model may not remove nodes") }
                if !work.children(of: n.id).isEmpty { throw ValidationError.cannotRemove(n.id, "not a leaf") }
                if author == .man && work.everHeldSlotOrDone(n.id) {
                    throw ValidationError.cannotRemove(n.id, "it has held a slot or been done")
                }
                removed[n.id] = n
                work.nodes.removeValue(forKey: n.id); touched.insert(n.id)
                for (k, other) in work.nodes where other.deps.contains(n.id) {
                    work.nodes[k]!.deps.removeAll { $0 == n.id }; touched.insert(k)
                }

            case .addDep(let rawID, let rawDep):
                let n = try node(rawID); let d = try node(rawDep)
                try checkModelMayTouch(n)
                if n.id == d.id { throw ValidationError.depOnSelf(n.id) }
                if work.depWouldCycle(id: n.id, dep: d.id) { throw ValidationError.depCycle(n.id, d.id) }
                if n.status == .doing && d.status != .done { throw ValidationError.wouldBlockDoing(n.id) }
                if !work.nodes[n.id]!.deps.contains(d.id) { work.nodes[n.id]!.deps.append(d.id) }
                touched.insert(n.id)

            case .removeDep(let rawID, let rawDep):
                let n = try node(rawID)
                try checkModelMayTouch(n)
                work.nodes[n.id]!.deps.removeAll { $0 == resolve(rawDep) }; touched.insert(n.id)

            case .setNode(let n):
                if author != .system { throw ValidationError.systemOnly }
                if work.nodes[n.id] == nil { added.insert(n.id) }
                work.nodes[n.id] = n; touched.insert(n.id); restored.insert(n.id)
                takeSlot(n.status, for: n.id)
            }
        }

        // Derive `blocked` (SPEC §3.1).
        var unblocked: [NodeID] = []
        for (k, n) in work.nodes {
            let unfinished = !work.unfinishedDeps(of: k).isEmpty
            if n.status == .open && unfinished { work.nodes[k]!.status = .blocked; touched.insert(k) }
            if n.status == .blocked && !unfinished { work.nodes[k]!.status = .open; touched.insert(k); unblocked.append(k) }
        }

        // Changes, inverse, timestamps.
        var changes: [StatusChange] = []
        var inverse: [Op] = []
        var reallyTouched: [NodeID] = []
        for id in touched.sorted() {
            let before = nodes[id] ?? removed[id]
            let after = work.nodes[id]
            if before == after { continue }
            reallyTouched.append(id)
            if let b = before, let a = after, b.status != a.status {
                changes.append(StatusChange(id: id, from: b.status, to: a.status))
            }
            if let b = before { inverse.append(.setNode(b)) }
            if after != nil, !restored.contains(id) { work.nodes[id]!.updatedAt = now }
        }
        // Added nodes are removed deepest-first so every removal is of a leaf.
        func depth(_ id: NodeID) -> Int { var d = 0; var c = work.nodes[id]?.parent; while let p = c { d += 1; c = work.nodes[p]?.parent }; return d }
        let removals = added.filter { nodes[$0] == nil }.sorted { depth($0) > depth($1) }.map { Op.removeNode(id: $0) }
        inverse = removals + inverse

        let entry = LogEntry(seq: patchLog.count + 1, at: now, author: author, base: version, ops: ops,
                             inverse: inverse, turnID: turnID, sessionID: session?.id,
                             round: (session?.state == .idle || session == nil) ? nil : session?.round,
                             changes: changes.sorted { $0.id < $1.id }, assignedIDs: assigned)
        work.patchLog.append(entry)
        work.version += 1
        self = work
        return ApplyResult(entry: entry, unblocked: unblocked.sorted())
    }

    /// Undo the most recent entry: applies its inverse as `system` and logs that.
    @discardableResult
    public mutating func undoLast(now: Date) throws -> ApplyResult? {
        guard let last = patchLog.last else { return nil }
        return try apply(last.inverse, author: .system, now: now)
    }
}
