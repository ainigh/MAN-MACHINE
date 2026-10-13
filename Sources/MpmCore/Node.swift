import Foundation

public typealias NodeID = String

/// SPEC §3.1
public enum Status: String, Codable, Equatable, Sendable, CaseIterable {
    case open, doing, next, blocked, done, crossedOut = "crossed_out"

    /// Statuses a node may hold while being a valid slot holder or commit candidate.
    public var isLive: Bool { self == .open || self == .doing || self == .next }
    public var isFinished: Bool { self == .done || self == .crossedOut }
}

public struct Node: Codable, Equatable, Sendable, Identifiable {
    public var id: NodeID
    public var title: String
    public var parent: NodeID?          // nil only for the root
    public var deps: [NodeID]
    public var status: Status
    public var due: Date?
    public var progress: Int            // 0..100
    public var description: String
    public var links: [String]
    public var aiNote: String
    public var flags: Set<String>
    public var createdAt: Date
    public var updatedAt: Date

    public static let flagNoSuggest = "no_suggest"
    public static let flagPinned = "pinned"

    public init(id: NodeID, title: String, parent: NodeID?, deps: [NodeID] = [], status: Status = .open,
                due: Date? = nil, progress: Int = 0, description: String = "", links: [String] = [],
                aiNote: String = "", flags: Set<String> = [], createdAt: Date, updatedAt: Date) {
        self.id = id; self.title = title; self.parent = parent; self.deps = deps; self.status = status
        self.due = due; self.progress = progress; self.description = description; self.links = links
        self.aiNote = aiNote; self.flags = flags; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var noSuggest: Bool { flags.contains(Node.flagNoSuggest) }
    public var pinned: Bool { flags.contains(Node.flagPinned) }
}

/// Opaque, sortable, never reused. ULID-shaped: 10 chars of time, 16 of randomness, Crockford base32.
public enum IDs {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func ulid(now: Date = Date(), random: () -> UInt8 = { UInt8.random(in: 0...31) }) -> NodeID {
        var ms = UInt64(now.timeIntervalSince1970 * 1000)
        var time = [Character](repeating: "0", count: 10)
        for i in (0..<10).reversed() { time[i] = alphabet[Int(ms & 31)]; ms >>= 5 }
        let rand = (0..<16).map { _ in alphabet[Int(random() & 31)] }
        return "n_" + String(time + rand)
    }
}
