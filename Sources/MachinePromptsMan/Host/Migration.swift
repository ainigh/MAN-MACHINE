import Foundation

enum PersistenceError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case newerSchema(Int)
    case noGenesis
    case logGap(expected: Int, found: Int)
    case replayFailed(seq: Int, reason: String)

    var description: String {
        switch self {
        case .unsupportedSchema(let v):
            return "store.json has schema version \(v). Migration from v1 (SPEC §18.1) is not implemented: no v1 stores exist."
        case .newerSchema(let v):
            return "store.json has schema version \(v), newer than this app understands (2). Update the app."
        case .noGenesis:
            return "store.json is unreadable and genesis.json is missing, so the patch log cannot be replayed."
        case .logGap(let e, let f):
            return "patch-log.jsonl skips from seq \(e - 1) to \(f); refusing to replay past a gap."
        case .replayFailed(let seq, let reason):
            return "replaying patch-log entry \(seq) failed: \(reason)"
        }
    }
}

/// SPEC §18.1. The hook stays so a future v1 import has one place to live.
enum Migration {
    static let currentSchema = 2

    static func v1to2(_ data: Data) throws -> Data {
        throw PersistenceError.unsupportedSchema(1)
    }

    /// Returns data decodable as the current schema, or throws. Never touches the file.
    static func upgrade(_ data: Data) throws -> Data {
        struct Probe: Decodable { var schemaVersion: Int? }
        guard let v = (try? JSONDecoder().decode(Probe.self, from: data))?.schemaVersion else { return data }
        if v > currentSchema { throw PersistenceError.newerSchema(v) }
        if v < 2 { return try v1to2(data) }
        return data
    }
}
