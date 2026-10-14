import Foundation
import MpmCore

/// The store on disk (tasks/01, SPEC §3.3, §12).
///
///     store.json        snapshot of the whole Store, pretty-printed, sorted keys
///     genesis.json      the store at version 0 (root and settings); the base for replay when
///                       store.json is unreadable, since the log alone does not record the root
///     patch-log.jsonl   one LogEntry per line, appended on every apply, ahead of the snapshot
///     turn-log.jsonl    SPEC §12, pruned at launch
///     system-log.jsonl  SPEC §12, pruned at launch
///
/// Snapshot cadence (SPEC §17): debounced 250 ms after a change, flushed on quit; no log compaction [default].
/// An unreadable snapshot is moved aside and rebuilt from genesis + log [default].
///
/// All file work happens on one serial queue. Every mutable property is touched only on that queue,
/// which is why the class can be `@unchecked Sendable`.
public final class Persistence: @unchecked Sendable {
    public let directory: URL
    /// Set before `load`; pruning happens there.
    public var retention: Retention
    let debounce: TimeInterval

    /// Test hook: called between the temp write and the rename of every snapshot.
    var beforeSnapshotRename: (@Sendable () throws -> Void)?

    private let queue = DispatchQueue(label: "MachinePromptsMan.persistence")
    private var pendingSnapshot: Store?
    private var flushScheduled = false
    private var writtenSeq = 0
    private var observer: (@Sendable (DiskEvent) -> Void)?
    private(set) var snapshotWrites = 0
    /// True when the last `load` found nothing and created the store (tasks/03 launch flow).
    public private(set) var createdFresh = false

    public var storeURL: URL { directory.appendingPathComponent("store.json") }
    public var genesisURL: URL { directory.appendingPathComponent("genesis.json") }
    public var patchLogURL: URL { directory.appendingPathComponent("patch-log.jsonl") }
    public var turnLogURL: URL { directory.appendingPathComponent("turn-log.jsonl") }
    public var systemLogURL: URL { directory.appendingPathComponent("system-log.jsonl") }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MachinePromptsMan", isDirectory: true)
    }

    public init(directory: URL = Persistence.defaultDirectory, retention: Retention = .default, debounce: TimeInterval = 0.25) {
        self.directory = directory
        self.retention = retention
        self.debounce = debounce
    }

    // MARK: Load

    /// Reads the store, catching up from the patch log when the snapshot is behind or unreadable.
    /// Creates a fresh store with root "Goal" when nothing exists. Throws only when continuing could
    /// lose data (an unsupported schema, an unreplayable log); the files are then left untouched.
    public func load(now: Date) throws -> Store {
        try queue.sync { try loadOnQueue(now: now) }
    }

    private func loadOnQueue(now: Date) throws -> Store {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for tmp in AtomicFile.leftovers(in: directory) {
            try? fm.removeItem(at: tmp)
            logOnQueue(now, .persistence, "removed \(tmp.lastPathComponent), left by an interrupted write")
        }
        let day: TimeInterval = 86_400
        if let n = try? JSONLines.prune(turnLogURL, olderThan: now - Double(retention.turnLogDays) * day), n > 0 {
            logOnQueue(now, .persistence, "turn log: pruned \(n) lines older than \(retention.turnLogDays) days")
        }
        if let n = try? JSONLines.prune(systemLogURL, olderThan: now - Double(retention.systemLogDays) * day), n > 0 {
            logOnQueue(now, .persistence, "system log: pruned \(n) lines older than \(retention.systemLogDays) days")
        }

        let (fileLog, badLines) = JSONLines.read(LogEntry.self, from: patchLogURL)

        var store: Store
        var dirty = false
        var unreadableSnapshot = false
        if let data = try? Data(contentsOf: storeURL) {
            let upgraded = try Migration.upgrade(data)
            if let s = try? JSONDecoder().decode(Store.self, from: upgraded) {
                store = s
            } else {
                store = try genesisOnQueue()
                unreadableSnapshot = true        // moved aside only once the replay below has succeeded
                dirty = true
            }
        } else if fm.fileExists(atPath: genesisURL.path) {
            logOnQueue(now, .persistence, "store.json missing; rebuilding from the patch log")
            store = try genesisOnQueue()
            dirty = true
        } else if !fileLog.isEmpty {
            throw PersistenceError.noGenesis
        } else {
            store = Store(rootTitle: "Goal", now: now)
            try AtomicFile.write(try Self.snapshotEncoder().encode(store), to: genesisURL)
            logOnQueue(now, .persistence, "created a new store")
            createdFresh = true
            dirty = true
        }

        if badLines > 0 {
            logOnQueue(now, .persistence, "patch log: skipped \(badLines) unreadable line(s)")
        }
        if fileLog.count > store.patchLog.count {
            let missing = Array(fileLog.dropFirst(store.patchLog.count))
            try Replay.catchUp(&store, with: missing)
            logOnQueue(now, .persistence, "snapshot was at version \(store.version - missing.count); replayed \(missing.count) patch-log entries as system")
            dirty = true
        }
        if unreadableSnapshot {
            // After the replay, so a log that cannot be replayed throws with the files as they were.
            let aside = directory.appendingPathComponent("store.corrupt-\(Int(now.timeIntervalSince1970)).json")
            try? fm.removeItem(at: aside)
            try fm.moveItem(at: storeURL, to: aside)
            logOnQueue(now, .persistence, "store.json unreadable; moved to \(aside.lastPathComponent), rebuilding from the patch log")
        }
        if badLines > 0 || fileLog.count < store.patchLog.count {
            // The snapshot carries the whole log (SPEC §3.3); make the file agree so appends continue at the right seq.
            try JSONLines.write(store.patchLog, to: patchLogURL)
            logOnQueue(now, .persistence, "patch-log.jsonl rewritten from the snapshot (\(store.patchLog.count) entries)")
        }

        // SPEC §14: an interruption is end_session. The map survives; the session does not.
        if let s = store.session {
            if s.state != .end {
                _ = Engine.handle(.endSession, store: &store, now: now)
                logOnQueue(now, .transition, "\(s.state.rawValue) → end: session \(s.id) (round \(s.round)) ended at launch")
            }
            store.session = nil
            dirty = true
        }

        writtenSeq = store.patchLog.count
        if dirty { try writeSnapshotOnQueue(store) }
        return store
    }

    private func genesisOnQueue() throws -> Store {
        guard let data = try? Data(contentsOf: genesisURL) else { throw PersistenceError.noGenesis }
        return try JSONDecoder().decode(Store.self, from: try Migration.upgrade(data))
    }

    // MARK: Write

    /// Reports writes and failures as they happen, on the persistence queue. The monitor panel listens.
    public func observe(_ f: @escaping @Sendable (DiskEvent) -> Void) {
        queue.sync { observer = f }
    }

    /// Call after every change to the store. Appends any new patch-log entries now (in order, ahead of
    /// the snapshot) and schedules a debounced snapshot.
    public func record(_ store: Store) {
        queue.async { [self] in
            let new = store.patchLog.dropFirst(writtenSeq)
            if !new.isEmpty {
                do {
                    var data = Data()
                    for e in new { data.append(try JSONLines.line(e)) }
                    try JSONLines.append(data, to: patchLogURL)
                    writtenSeq = store.patchLog.count
                    observer?(.patchLogAppended(new.count))
                } catch {
                    logOnQueue(Date(), .persistence, "patch-log append failed: \(error)")
                    observer?(.failed("patch-log append failed: \(error)"))
                }
            }
            pendingSnapshot = store
            if !flushScheduled {
                flushScheduled = true
                queue.asyncAfter(deadline: .now() + debounce) { [self] in writePendingOnQueue() }
            }
        }
    }

    /// Writes any pending snapshot now and waits for it. Call on quit.
    public func flush() {
        queue.sync { writePendingOnQueue() }
    }

    /// Waits for queued appends without forcing the debounced snapshot. Tests use it to stand in for
    /// a crash: the log is on disk, the snapshot is not.
    func waitForQueuedWrites() {
        queue.sync {}
    }

    public func appendSystem(_ record: SystemLogRecord) {
        queue.async { [self] in logOnQueue(record) }
    }

    public func appendTurn(_ record: TurnLogRecord) {
        queue.async { [self] in
            do { try JSONLines.append(try JSONLines.line(record), to: turnLogURL) } catch {
                logOnQueue(record.at, .persistence, "turn-log append failed: \(error)")
                observer?(.failed("turn-log append failed: \(error)"))
            }
        }
    }

    private func writePendingOnQueue() {
        flushScheduled = false
        guard let s = pendingSnapshot else { return }
        pendingSnapshot = nil
        do {
            try writeSnapshotOnQueue(s)
            observer?(.snapshotWritten(version: s.version))
        } catch {
            logOnQueue(Date(), .persistence, "snapshot write failed: \(error)")
            observer?(.failed("snapshot write failed: \(error)"))
        }
    }

    private func writeSnapshotOnQueue(_ store: Store) throws {
        try AtomicFile.write(try Self.snapshotEncoder().encode(store), to: storeURL, beforeRename: beforeSnapshotRename)
        snapshotWrites += 1
    }

    private func logOnQueue(_ at: Date, _ kind: SystemLogRecord.Kind, _ message: String) {
        logOnQueue(SystemLogRecord(at: at, kind: kind, message: message))
    }

    private func logOnQueue(_ record: SystemLogRecord) {
        // The system log is the last place to report a failure; if it cannot be written there is nowhere further.
        try? JSONLines.append(try JSONLines.line(record), to: systemLogURL)
    }

    static func snapshotEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

/// What the disk did, for the monitor panel. Failures are also in the system log.
public enum DiskEvent: Equatable, Sendable {
    case patchLogAppended(Int)
    case snapshotWritten(version: Int)
    case failed(String)
}
