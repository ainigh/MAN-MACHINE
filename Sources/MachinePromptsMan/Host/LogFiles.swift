import Foundation
import MpmCore

/// SPEC §12 system log: transitions, announcements, policy decisions, adapter errors,
/// persistence events, schedule firings.
struct SystemLogRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case transition, effect, announcement, policy, adapter, persistence, schedule
    }
    var at: Date
    var kind: Kind
    var message: String
}

/// SPEC §12 turn log. Filled in by the turn engine (task 07); the shape is fixed here so retention
/// and the file format exist from the start.
struct TurnLogRecord: Codable, Equatable, Sendable {
    var at: Date
    var turnID: String
    var trigger: String
    var projection: String
    var prompt: String
    var raw: String?
    var ladderStep: Int?
    var validation: String?
    var outcome: String
    var latencyMs: Int?
    var deadlineMet: Bool?
}

/// SPEC §12 default retention. Becomes a setting in task 09.
struct Retention: Equatable, Sendable {
    var turnLogDays: Int = 90
    var systemLogDays: Int = 30
    static let `default` = Retention()
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
