import Foundation

/// SPEC §4. Exactly four keys. Frozen for 2.x.
public struct Envelope: Codable, Equatable, Sendable {
    public var say: String
    public var ask: String?
    public var patch: [Op]
    public var next: Date?

    public init(say: String = "", ask: String? = nil, patch: [Op] = [], next: Date? = nil) {
        self.say = say; self.ask = ask; self.patch = patch; self.next = next
    }
}

public enum ParseStep: Int, Codable, Sendable, Equatable {
    case envelopeFence = 1, anyFence, braceSubstring, lineOriented, proseOnly
}

public struct ParseOutcome: Equatable, Sendable {
    public var envelope: Envelope
    public var step: ParseStep
    /// Keys dropped (SPEC §13 #9) and ops that could not be decoded (patch then emptied: the ladder never invents ops).
    public var warnings: [String]
}

/// SPEC §9.3 — the degradation ladder. Pure; the repair pass (a second model call) is the host's job.
public enum EnvelopeParser {

    public static func parse(_ raw: String) -> ParseOutcome {
        if let fence = fencedBlock(raw, tag: "envelope"), let o = fromJSON(fence, step: .envelopeFence) { return o }
        for fence in allFencedBlocks(raw) {
            if let o = fromJSON(fence, step: .anyFence), o.envelope.say != "" || o.envelope.patch.count > 0 || o.envelope.ask != nil { return o }
        }
        if let brace = firstBraceSubstring(raw), let o = fromJSON(brace, step: .braceSubstring) { return o }
        if let o = lineOriented(raw) { return o }
        return ParseOutcome(envelope: Envelope(say: raw.trimmingCharacters(in: .whitespacesAndNewlines)), step: .proseOnly, warnings: [])
    }

    // MARK: Steps

    static func fencedBlock(_ s: String, tag: String) -> String? {
        guard let r = s.range(of: "```" + tag) else { return nil }
        let after = s[r.upperBound...]
        guard let end = after.range(of: "```") else { return nil }
        return String(after[..<end.lowerBound])
    }

    static func allFencedBlocks(_ s: String) -> [String] {
        var out: [String] = []
        var rest = s[...]
        while let open = rest.range(of: "```") {
            let afterOpen = rest[open.upperBound...]
            guard let nl = afterOpen.firstIndex(of: "\n") else { break }
            let body = afterOpen[afterOpen.index(after: nl)...]
            guard let close = body.range(of: "```") else { break }
            out.append(String(body[..<close.lowerBound]))
            rest = body[close.upperBound...]
        }
        return out
    }

    static func firstBraceSubstring(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0; var inString = false; var escape = false
        for i in s.indices[start...] {
            let c = s[i]
            if inString {
                if escape { escape = false } else if c == "\\" { escape = true } else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true } else if c == "{" { depth += 1 } else if c == "}" {
                depth -= 1
                if depth == 0 { return String(s[start...i]) }
            }
        }
        return nil
    }

    static func lineOriented(_ s: String) -> ParseOutcome? {
        var say: [String] = []; var ask: String? = nil; var next: Date? = nil; var hit = false
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("say:") { say.append(String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces)); hit = true }
            else if t.lowercased().hasPrefix("ask:") { ask = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces); hit = true }
            else if t.lowercased().hasPrefix("next:") { next = parseDate(String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)); hit = true }
        }
        guard hit else { return nil }
        return ParseOutcome(envelope: Envelope(say: say.joined(separator: "\n"), ask: ask, patch: [], next: next), step: .lineOriented, warnings: [])
    }

    static func fromJSON(_ text: String, step: ParseStep) -> ParseOutcome? {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var warnings: [String] = []
        let allowed: Set<String> = ["say", "ask", "patch", "next"]
        for k in obj.keys where !allowed.contains(k) { warnings.append("dropped key \(k)") }
        guard obj["say"] != nil || step == .envelopeFence else { return nil }
        let say = (obj["say"] as? String) ?? ""
        let ask = obj["ask"] as? String
        let next = (obj["next"] as? String).flatMap(parseDate)
        var ops: [Op] = []
        if let rawOps = obj["patch"] as? [[String: Any]] {
            for (i, o) in rawOps.enumerated() {
                if let op = decodeOp(o) { ops.append(op) } else { warnings.append("op \(i) not decodable; patch dropped"); ops = []; break }
            }
        } else if obj["patch"] != nil, !(obj["patch"] is NSNull) {
            if let arr = obj["patch"] as? [Any], arr.isEmpty { } else { warnings.append("patch is not an array; dropped") }
        }
        return ParseOutcome(envelope: Envelope(say: say, ask: ask, patch: ops, next: next), step: step, warnings: warnings)
    }

    // MARK: Op decoding (SPEC §5.1 wire format: snake_case keys)

    static func decodeOp(_ o: [String: Any]) -> Op? {
        guard let kind = o["op"] as? String else { return nil }
        func s(_ k: String) -> String? { o[k] as? String }
        func status(_ k: String) -> Status?? {
            guard let v = o[k] else { return .some(nil) }
            guard let str = v as? String, let st = Status(rawValue: str), st != .blocked else { return nil }
            return .some(st)
        }
        switch kind {
        case "add_node":
            guard let tmp = s("tmp_id"), let parent = s("parent"), let title = s("title"), let st = status("status") else { return nil }
            return .addNode(tmpID: tmp, parent: parent, title: title, status: st, due: s("due").flatMap(parseDate),
                            progress: o["progress"] as? Int, description: s("description"))
        case "update_node":
            guard let id = s("id"), let f = o["fields"] as? [String: Any] else { return nil }
            var fields = NodeFields()
            if let t = f["title"] as? String { fields.title = t }
            if let st = f["status"] { guard let str = st as? String, let v = Status(rawValue: str), v != .blocked else { return nil }; fields.status = v }
            if f["due"] is NSNull { fields.clearDue = true } else if let d = f["due"] as? String { guard let date = parseDate(d) else { return nil }; fields.due = date }
            if let p = f["progress"] as? Int { fields.progress = p }
            if let d = f["description"] as? String { fields.description = d }
            if let l = f["links"] as? [String] { fields.links = l }
            if let a = f["ai_note"] as? String { fields.aiNote = a }
            if let fl = f["flags"] as? [String] { fields.flags = Set(fl) }
            for k in f.keys where !["title", "status", "due", "progress", "description", "links", "ai_note", "flags"].contains(k) { return nil }
            return .updateNode(id: id, fields: fields)
        case "move_node":
            guard let id = s("id"), let p = s("parent") else { return nil }
            return .moveNode(id: id, parent: p)
        case "cross_out": guard let id = s("id") else { return nil }; return .crossOut(id: id)
        case "restore": guard let id = s("id") else { return nil }; return .restore(id: id)
        case "remove_node": guard let id = s("id") else { return nil }; return .removeNode(id: id)
        case "add_dep": guard let id = s("id"), let d = s("dep") else { return nil }; return .addDep(id: id, dep: d)
        case "remove_dep": guard let id = s("id"), let d = s("dep") else { return nil }; return .removeDep(id: id, dep: d)
        default: return nil
        }
    }

    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // "2026-10-14T09:00" or "2026-10-14" (local, as the template shows)
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
