import Foundation
import MpmCore

/// SPEC §12 system log: transitions, announcements, policy decisions, adapter errors,
/// persistence events, schedule firings.
public struct SystemLogRecord: Codable, Equatable, Sendable {
    public init(at: Date, kind: Kind, message: String) { self.at = at; self.kind = kind; self.message = message }
    public enum Kind: String, Codable, Sendable {
        case transition, effect, announcement, policy, adapter, persistence, schedule
    }
    public var at: Date
    public var kind: Kind
    public var message: String
}

/// SPEC §12 turn log. Filled in by the turn engine (task 07); the shape is fixed here so retention
/// and the file format exist from the start.
public struct TurnLogRecord: Codable, Equatable, Sendable {
    public var at: Date
    public var turnID: String
    public var trigger: String
    public var projection: String
    public var prompt: String
    public var raw: String?
    public var ladderStep: Int?
    public var validation: String?
    public var outcome: String
    public var latencyMs: Int?
    public var deadlineMet: Bool?

    public init(at: Date, turnID: String, trigger: String, projection: String, prompt: String, raw: String? = nil,
                ladderStep: Int? = nil, validation: String? = nil, outcome: String, latencyMs: Int? = nil,
                deadlineMet: Bool? = nil) {
        self.at = at; self.turnID = turnID; self.trigger = trigger; self.projection = projection; self.prompt = prompt
        self.raw = raw; self.ladderStep = ladderStep; self.validation = validation; self.outcome = outcome
        self.latencyMs = latencyMs; self.deadlineMet = deadlineMet
    }
}

/// SPEC §12 default retention. Becomes a setting in task 09.
public struct Retention: Equatable, Sendable {
    public var turnLogDays: Int = 90
    public var systemLogDays: Int = 30
    public init(turnLogDays: Int = 90, systemLogDays: Int = 30) { self.turnLogDays = turnLogDays; self.systemLogDays = systemLogDays }
    public static let `default` = Retention()
}

/// One JSON value per line. Appends are whole lines; a crash mid-append can leave at most one
/// torn final line, which `read` skips and reports.
enum JSONLines {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func line<T: Encodable>(_ value: T) throws -> Data {
        var d = try encoder().encode(value)
        d.append(0x0A)
        return d
    }

    static func append(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: data)
    }

    /// Decoded values in file order, plus the number of lines that did not decode.
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> (values: [T], bad: Int) {
        guard let data = try? Data(contentsOf: url) else { return ([], 0) }
        let dec = JSONDecoder()
        var out: [T] = []; var bad = 0
        for raw in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let v = try? dec.decode(T.self, from: Data(raw)) { out.append(v) } else { bad += 1 }
        }
        return (out, bad)
    }

    static func write<T: Encodable>(_ values: [T], to url: URL) throws {
        var data = Data()
        for v in values { data.append(try line(v)) }
        try AtomicFile.write(data, to: url)
    }

    private struct Stamp: Decodable { var at: Date }

    /// Drops lines older than `cutoff` (and lines without a readable `at`). Returns how many were dropped.
    @discardableResult
    static func prune(_ url: URL, olderThan cutoff: Date) throws -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let dec = JSONDecoder()
        var kept = Data(); var dropped = 0
        for raw in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let s = try? dec.decode(Stamp.self, from: Data(raw)), s.at >= cutoff {
                kept.append(contentsOf: raw); kept.append(0x0A)
            } else {
                dropped += 1
            }
        }
        if dropped > 0 { try AtomicFile.write(kept, to: url) }
        return dropped
    }
}
