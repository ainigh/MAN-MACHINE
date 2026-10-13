import Foundation

public enum Author: String, Codable, Equatable, Sendable { case man, model, system }

/// Fields `update_node` may set. `nil` means "leave as is". `clearDue` removes the due date.
public struct NodeFields: Codable, Equatable, Sendable {
    public var title: String?
    public var status: Status?
    public var due: Date?
    public var clearDue: Bool
    public var progress: Int?
    public var description: String?
    public var links: [String]?
    public var aiNote: String?
    public var flags: Set<String>?

    public init(title: String? = nil, status: Status? = nil, due: Date? = nil, clearDue: Bool = false,
                progress: Int? = nil, description: String? = nil, links: [String]? = nil,
                aiNote: String? = nil, flags: Set<String>? = nil) {
        self.title = title; self.status = status; self.due = due; self.clearDue = clearDue
        self.progress = progress; self.description = description; self.links = links
        self.aiNote = aiNote; self.flags = flags
    }
}

/// SPEC §5.1. `tmpID` values are referenced by later ops in the same patch as "tmp:<tmpID>".
public enum Op: Codable, Equatable, Sendable {
    case addNode(tmpID: String, parent: NodeID, title: String, status: Status?, due: Date?, progress: Int?, description: String?)
    case updateNode(id: NodeID, fields: NodeFields)
    case moveNode(id: NodeID, parent: NodeID)
    case crossOut(id: NodeID)
    case restore(id: NodeID)
    case removeNode(id: NodeID)
    case addDep(id: NodeID, dep: NodeID)
    case removeDep(id: NodeID, dep: NodeID)
    /// System only. Replaces (or recreates) a node wholesale. Used in inverses so undo is exact.
    case setNode(Node)

    public static func add(_ title: String, under parent: NodeID, tmp: String = "new", status: Status? = nil) -> Op {
        .addNode(tmpID: tmp, parent: parent, title: title, status: status, due: nil, progress: nil, description: nil)
    }
    public static func setStatus(_ id: NodeID, _ status: Status) -> Op {
        .updateNode(id: id, fields: NodeFields(status: status))
    }
    public static func tmp(_ tmpID: String) -> NodeID { "tmp:" + tmpID }

    /// The node ids an op reads or writes (before tmp resolution).
    public var touchedIDs: [NodeID] {
        switch self {
        case .addNode(let t, let p, _, _, _, _, _): return [Op.tmp(t), p]
        case .updateNode(let id, _), .crossOut(let id), .restore(let id), .removeNode(let id): return [id]
        case .moveNode(let id, let p): return [id, p]
        case .addDep(let id, let d), .removeDep(let id, let d): return [id, d]
        case .setNode(let n): return [n.id]
        }
    }
}

public struct StatusChange: Codable, Equatable, Sendable {
    public var id: NodeID
    public var from: Status
    public var to: Status
}

/// SPEC §3.3
public struct LogEntry: Codable, Equatable, Sendable {
    public var seq: Int
    public var at: Date
    public var author: Author
    public var base: Int
    public var ops: [Op]
    public var inverse: [Op]
    public var turnID: String?
    public var sessionID: String?
    public var round: Int?
    /// Net status changes this entry caused (from → to), one per node. Used for x and the round diff.
    public var changes: [StatusChange]
    /// tmp id → real id assigned for `addNode` ops in this entry.
    public var assignedIDs: [String: NodeID]
}

// MARK: - Small system state (SPEC §3.4)

public struct Proposal: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var turnID: String
    public var at: Date
    public var ops: [Op]
    public var say: String
    public var expiresAt: Date?
    public var stale: Bool
    public init(id: String, turnID: String, at: Date, ops: [Op], say: String, expiresAt: Date? = nil, stale: Bool = false) {
        self.id = id; self.turnID = turnID; self.at = at; self.ops = ops; self.say = say; self.expiresAt = expiresAt; self.stale = stale
    }
}

public struct PendingQuestion: Codable, Equatable, Sendable {
    public var turnID: String
    public var at: Date
    public var text: String
    public var expiresAt: Date
    public init(turnID: String, at: Date, text: String, expiresAt: Date) {
        self.turnID = turnID; self.at = at; self.text = text; self.expiresAt = expiresAt
    }
}

public struct Declined: Codable, Equatable, Sendable {
    public var nodeIDs: [NodeID]
    public var summary: String
    public var at: Date
    public var expiresAt: Date
    public init(nodeIDs: [NodeID], summary: String, at: Date, expiresAt: Date) {
        self.nodeIDs = nodeIDs; self.summary = summary; self.at = at; self.expiresAt = expiresAt
    }
}

public enum ScheduleSource: String, Codable, Sendable { case man, model }

public struct ScheduleEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var at: Date
    public var reason: String
    public var source: ScheduleSource
    public init(id: String, at: Date, reason: String, source: ScheduleSource) {
        self.id = id; self.at = at; self.reason = reason; self.source = source
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var session: SessionConfig
    public var maxOpsPerPatch: Int
    public var maxNewNodesPerPatch: Int
    public var lenientValidation: Bool
    public var repairPass: Bool
    public var dueSoonDays: Int
    public var staleDays: Int
    public var driftDays: Int
    public var declinedTTLDays: Int
    public var descriptionMaxChars: Int
    public var projectionMaxChars: Int
    public var maxNudgesPerDay: Int
    public var quietHoursStart: Int   // hour of day, local; 22
    public var quietHoursEnd: Int     // 8
    public var minModelIntervalMinutes: Int
    public var maxModelIntervalHours: Int
    public var timezone: String

    public static let `default` = Settings(
        session: .default, maxOpsPerPatch: 12, maxNewNodesPerPatch: 5, lenientValidation: false,
        repairPass: true, dueSoonDays: 3, staleDays: 7, driftDays: 5, declinedTTLDays: 14,
        descriptionMaxChars: 200, projectionMaxChars: 12_000, maxNudgesPerDay: 6,
        quietHoursStart: 22, quietHoursEnd: 8, minModelIntervalMinutes: 30, maxModelIntervalHours: 72,
        timezone: TimeZone.current.identifier)
}
