import Foundation

public struct RuleHit: Equatable, Sendable, Codable {
    public var rule: String
    public var nodeID: NodeID
}

/// SPEC §8.1
public enum Trigger: Equatable, Sendable {
    case message(String)
    case answer(String)
    case phase                      // STATUS entry; the session carries the summary
    case schedule(source: ScheduleSource, reason: String)
    case initiative([RuleHit])

    public var kind: String {
        switch self {
        case .message: return "message"; case .answer: return "answer"; case .phase: return "phase"
        case .schedule: return "schedule"; case .initiative: return "initiative"
        }
    }
}

/// SPEC §8.2 — deterministic rules. They decide *that*; the model decides *how to say it*.
public enum InitiativeRules {
    public static func evaluate(_ store: Store, now: Date) -> [RuleHit] {
        let s = store.settings
        let day: TimeInterval = 86_400
        var hits: [RuleHit] = []
        for n in store.nodes.values.sorted(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }) where n.id != store.rootID && !n.noSuggest {
            if let due = n.due, !n.status.isFinished {
                if due < now { hits.append(RuleHit(rule: "overdue", nodeID: n.id)) }
                else if due.timeIntervalSince(now) <= Double(s.dueSoonDays) * day { hits.append(RuleHit(rule: "due_soon", nodeID: n.id)) }
            }
            if (n.status == .doing || n.status == .next), now.timeIntervalSince(n.updatedAt) > Double(s.staleDays) * day {
                hits.append(RuleHit(rule: "stale", nodeID: n.id))
            }
            if n.status == .doing, now.timeIntervalSince(lastProgressChange(n.id, store)) > Double(s.driftDays) * day {
                hits.append(RuleHit(rule: "drift", nodeID: n.id))
            }
        }
        return hits
    }

    static func lastProgressChange(_ id: NodeID, _ store: Store) -> Date {
        for e in store.patchLog.reversed() {
            for op in e.ops {
                if case .updateNode(let oid, let f) = op, oid == id, f.progress != nil { return e.at }
            }
        }
        return store.nodes[id]?.createdAt ?? .distantPast
    }
}

/// SPEC §7. `project(store, trigger, now)` is pure.
public enum Projection {

    public static func project(_ store: Store, trigger: Trigger, now: Date, hits: [RuleHit] = []) -> String {
        var lines: [String] = []
        let tz = TimeZone(identifier: store.settings.timezone) ?? .current
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = tz
        df.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        lines.append("now: \(df.string(from: now)) \(tz.identifier)")

        switch trigger {
        case .message(let t): lines.append("trigger: message\nhuman: \(t)")
        case .answer(let t): lines.append("trigger: answer\nhuman: \(t)")
        case .phase: lines.append("trigger: phase (round boundary)")
        case .schedule(let src, let reason): lines.append("trigger: schedule (\(src.rawValue)): \(reason)")
        case .initiative(let h): lines.append("trigger: initiative: " + h.map { "\($0.rule) \($0.nodeID)" }.joined(separator: ", "))
        }

        if let s = store.session, s.state != .end, s.state != .idle, let from = s.roundStart {
            let c = s.config
            var head = "session: round \(s.round), R \(Announcement.fmt(c.R)), z \(s.z)/\(c.zMax)"
            if let x = s.x { head += ", x \(x)" }
            if let l = s.statusLength { head += ", status \(Announcement.fmt(l))" }
            head += ", seated \(Announcement.fmt(s.seated(at: now)))"
            lines.append(head)
            let diff = Metrics.roundDiff(in: store, from: from, to: now)
            if !diff.isEmpty {
                lines.append("round diff: " + diff.map { "\($0.id) \($0.from.rawValue)→\($0.to.rawValue)" }.joined(separator: ", "))
            }
        }

        if let q = store.question { lines.append("pending question (asked earlier): \(q.text)") }

        let declined = store.declined.filter { $0.expiresAt > now }
        if !declined.isEmpty {
            lines.append("declined recently:\n" + declined.map { "- \($0.summary)" }.joined(separator: "\n"))
        }
        if case .initiative = trigger { } else if !hits.isEmpty {
            lines.append("rule hits:\n" + hits.map { "- \($0.rule) \($0.nodeID)" }.joined(separator: "\n"))
        }

        lines.append("")
        lines.append(renderGraph(store, now: now))
        return lines.joined(separator: "\n")
    }

    // MARK: Graph rendering (SPEC §7.2–7.3)

    public static func renderGraph(_ store: Store, now: Date) -> String {
        var focus = Set<NodeID>()
        if let d = store.doing { focus.insert(d.id) }
        if let n = store.next { focus.insert(n.id) }
        var dropped = Set<NodeID>()
        var text = render(store, now: now, dropped: dropped)
        // SPEC §7.2 cap: drop open nodes furthest from the focus nodes first.
        let cap = store.settings.projectionMaxChars
        if text.count > cap {
            let candidates = store.nodes.values
                .filter { $0.status == .open && $0.id != store.rootID && !focus.contains($0.id) }
                .sorted { distance($0.id, from: focus, store) > distance($1.id, from: focus, store) }
            for c in candidates where text.count > cap {
                dropped.insert(c.id)
                text = render(store, now: now, dropped: dropped)
            }
        }
        return text
    }

    static func distance(_ id: NodeID, from focus: Set<NodeID>, _ store: Store) -> Int {
        guard !focus.isEmpty else { return 0 }
        func ancestors(_ x: NodeID) -> [NodeID] {
            var out = [x]; var cur = store.nodes[x]?.parent
            while let c = cur { out.append(c); cur = store.nodes[c]?.parent }
            return out
        }
        let mine = ancestors(id)
        var best = Int.max
        for f in focus {
            let theirs = ancestors(f)
            for (i, a) in mine.enumerated() { if let j = theirs.firstIndex(of: a) { best = min(best, i + j); break } }
        }
        return best == Int.max ? 0 : best
    }

    static func render(_ store: Store, now: Date, dropped: Set<NodeID>) -> String {
        var out: [String] = []
        func walk(_ id: NodeID, depth: Int) {
            guard let n = store.nodes[id] else { return }
            let kids = store.children(of: id)
            let pad = String(repeating: "  ", count: depth)
            let full = n.pinned || n.status == .doing || n.status == .next || n.status == .blocked
                || (n.due.map { $0 < now && !n.status.isFinished } ?? false) || id == store.rootID
            if n.noSuggest && id != store.rootID {
                out.append("\(pad)[\(n.id)] \(n.title)  [locked]")
                return
            }
            if n.status.isFinished && id != store.rootID {
                let tag = n.status == .done ? "done" : "x"
                out.append("\(pad)[\(n.id)] \(n.title)  [\(tag)]\(kids.isEmpty ? "" : " (\(countDescendants(id, store)) children)")")
                return
            }
            if dropped.contains(id) { return }
            var attrs: [String] = [n.status.rawValue]
            if let d = n.due { attrs.append("due " + shortDate(d)) }
            if n.progress > 0 { attrs.append("\(n.progress)%") }
            if full {
                let days = Int(now.timeIntervalSince(n.updatedAt) / 86_400)
                attrs.append(days == 0 ? "updated today" : "updated \(days)d ago")
                if !n.deps.isEmpty { attrs.append("deps " + n.deps.joined(separator: ",")) }
            }
            out.append("\(pad)[\(n.id)] \(n.title)  (\(attrs.joined(separator: ", ")))")
            let desc = truncate(n.description, store.settings.descriptionMaxChars)
            if !desc.isEmpty { out.append("\(pad)  \(desc)") }
            if full, !n.aiNote.isEmpty { out.append("\(pad)  note: \(n.aiNote)") }
            for k in kids { walk(k.id, depth: depth + 1) }
        }
        walk(store.rootID, depth: 0)
        return out.joined(separator: "\n")
    }

    static func countDescendants(_ id: NodeID, _ store: Store) -> Int {
        store.children(of: id).reduce(0) { $0 + 1 + countDescendants($1.id, store) }
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    static func truncate(_ s: String, _ n: Int) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ")
        return t.count <= n ? t : String(t.prefix(max(0, n - 1))) + "…"
    }
}
