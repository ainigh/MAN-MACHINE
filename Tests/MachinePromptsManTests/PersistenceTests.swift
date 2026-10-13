import XCTest
import MpmCore
@testable import MpmHost

final class PersistenceTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mpm-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func persistence(debounce: TimeInterval = 0.25) -> Persistence {
        Persistence(directory: dir, debounce: debounce)
    }

    /// A history that exercises replay: tmp references inside one patch, add-with-status, slot
    /// displacement, deps and blocked derivation, cross-out cascade, an undo (set_node/remove_node inverses).
    func buildHistory(_ store: inout Store, from t: Date) throws {
        let root = store.rootID
        let a = try store.apply([.add("A", under: root, tmp: "a"), .add("A1", under: Op.tmp("a"), tmp: "a1"),
                                 .add("B", under: root, tmp: "b", status: .doing)], author: .man, now: t + 1)
        let A = a.entry.assignedIDs["a"]!, A1 = a.entry.assignedIDs["a1"]!, B = a.entry.assignedIDs["b"]!
        try store.apply([.add("C", under: A, tmp: "c"), .addDep(id: Op.tmp("c"), dep: A1)], author: .man, now: t + 2)
        try store.apply([.setStatus(A, .doing), .setStatus(B, .next)], author: .man, now: t + 3)
        try store.apply([.setStatus(A1, .done)], author: .man, now: t + 4)
        try store.apply([.add("D", under: B, tmp: "d")], author: .man, now: t + 5)
        try store.undoLast(now: t + 6)
        try store.apply([.crossOut(id: B)], author: .man, now: t + 7)
        try store.apply([.updateNode(id: A, fields: NodeFields(progress: 40, aiNote: "batch on Fridays"))],
                        author: .system, now: t + 8)
    }

    // MARK: Acceptance

    func testFreshStoreHasGoalRoot() throws {
        let s = try persistence().load(now: t0)
        XCTAssertEqual(s.nodes[s.rootID]?.title, "Goal")
        XCTAssertEqual(s.version, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("genesis.json").path))
    }

    func testRoundTripWithSessionEndsTheSessionKeepsTheMap() throws {
        let p = persistence()
        var s = try p.load(now: t0)
        try buildHistory(&s, from: t0)
        _ = Engine.handle(.startSession, store: &s, now: t0 + 10)
        let open = s.nodes.values.filter { $0.status == .open }.map(\.id).sorted()
        _ = try Engine.applyPatch([.add("E", under: s.rootID, tmp: "e")], author: .man, store: &s, now: t0 + 11)
        _ = Engine.handle(.commit(doing: s.doing!.id, next: open.first ?? s.nodes.values.first { $0.title == "E" }!.id),
                          store: &s, now: t0 + 12)
        XCTAssertEqual(s.session?.state, .work)
        p.record(s)
        p.flush()

        let back = try persistence().load(now: t0 + 100)
        XCTAssertNil(back.session)
        var expected = s; expected.session = nil
        XCTAssertEqual(back, expected)
        XCTAssertTrue(systemLog().contains { $0.kind == .transition && $0.message.contains("ended at launch") })
    }

    func testCorruptSnapshotLoadsFromTheLogAlone() throws {
        let p = persistence()
        var s = try p.load(now: t0)
        try buildHistory(&s, from: t0)
        p.record(s); p.flush()
        try Data("{\"nodes\": [tor".utf8).write(to: dir.appendingPathComponent("store.json"))

        let back = try persistence().load(now: t0 + 100)
        XCTAssertEqual(back.nodes, s.nodes)
        XCTAssertEqual(back.patchLog, s.patchLog)
        XCTAssertEqual(back.version, s.version)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("store.corrupt-") })
        XCTAssertTrue(systemLog().contains { $0.message.contains("rebuilding from the patch log") })
    }

    func testSnapshotBehindLogIsCaughtUpByReplay() throws {
        let p = persistence(debounce: 3600)    // the snapshot never lands on its own: a crash after the appends
        var s = try p.load(now: t0)
        try s.apply([.add("early", under: s.rootID)], author: .man, now: t0 + 0.5)
        p.record(s); p.flush()                 // snapshot at version 1
        try buildHistory(&s, from: t0)
        p.record(s); p.waitForQueuedWrites()   // log at version 9, snapshot still at 1

        let back = try persistence().load(now: t0 + 100)
        XCTAssertEqual(back.nodes, s.nodes)
        XCTAssertEqual(back.patchLog, s.patchLog)
        XCTAssertTrue(systemLog().contains { $0.message.contains("replayed 8 patch-log entries as system") })
    }

    func testTornFinalLogLineIsSkippedAndRepaired() throws {
        let p = persistence()
        var s = try p.load(now: t0)
        try buildHistory(&s, from: t0)
        p.record(s); p.flush()
        try JSONLines.append(Data("{\"seq\":9,\"at\":".utf8), to: p.patchLogURL)

        let back = try persistence().load(now: t0 + 100)
        XCTAssertEqual(back.patchLog, s.patchLog)
        XCTAssertEqual(JSONLines.read(LogEntry.self, from: p.patchLogURL).bad, 0)
        XCTAssertEqual(JSONLines.read(LogEntry.self, from: p.patchLogURL).values.count, s.patchLog.count)
    }

    func testRetentionPrunes() throws {
        let p = persistence()
        _ = try p.load(now: t0)
        let day: TimeInterval = 86_400
        for age in [0.0, 29, 31, 89, 91] {
            p.appendSystem(SystemLogRecord(at: t0 - age * day, kind: .schedule, message: "age \(Int(age))"))
            p.appendTurn(TurnLogRecord(at: t0 - age * day, turnID: "age \(Int(age))", trigger: "phase",
                                       projection: "", prompt: "", outcome: "ok"))
        }
        p.flush()

        _ = try persistence().load(now: t0)
        let sys = systemLog().filter { $0.kind == .schedule }.map(\.message)
        XCTAssertEqual(sys, ["age 0", "age 29"])
        let turns = JSONLines.read(TurnLogRecord.self, from: p.turnLogURL).values.map(\.turnID)
        XCTAssertEqual(turns, ["age 0", "age 29", "age 31", "age 89"])
    }

    func testCrashBetweenTempWriteAndRenameLeavesTheOldFile() throws {
        let p = persistence()
        var s = try p.load(now: t0)
        try s.apply([.add("kept", under: s.rootID)], author: .man, now: t0 + 1)
        p.record(s); p.flush()
        let before = try Data(contentsOf: p.storeURL)

        struct Crash: Error {}
        p.beforeSnapshotRename = { throw Crash() }
        try s.apply([.add("lost from the snapshot, kept in the log", under: s.rootID)], author: .man, now: t0 + 2)
        p.record(s); p.flush()

        XCTAssertEqual(try Data(contentsOf: p.storeURL), before)
        XCTAssertFalse(AtomicFile.leftovers(in: dir).isEmpty)

        let back = try persistence().load(now: t0 + 100)
        XCTAssertTrue(AtomicFile.leftovers(in: dir).isEmpty)
        XCTAssertEqual(back.nodes, s.nodes)     // the log carried the second patch
    }

    func testBurstOfWritesWithCrashesIsNeverTorn() throws {
        let url = dir.appendingPathComponent("burst.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        struct Crash: Error {}
        var onDisk: Int? = nil
        for i in 0..<200 {
            let payload = try JSONEncoder().encode(Array(repeating: i, count: 1 + (i * 37) % 4000))
            let crash = i % 3 == 1
            do {
                try AtomicFile.write(payload, to: url, beforeRename: crash ? { throw Crash() } : nil)
                onDisk = i
            } catch is Crash {}
            let read = try JSONDecoder().decode([Int].self, from: Data(contentsOf: url))
            XCTAssertEqual(read.first, onDisk)
            XCTAssertEqual(Set(read).count, 1)
        }
    }

    func testV1StoreThrowsAndIsLeftUntouched() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1 = Data("{\"schemaVersion\":1,\"nodes\":[]}".utf8)
        try v1.write(to: dir.appendingPathComponent("store.json"))
        XCTAssertThrowsError(try persistence().load(now: t0)) { e in
            XCTAssertEqual(e as? PersistenceError, .unsupportedSchema(1))
        }
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("store.json")), v1)
    }

    func testUnrecoverableStoreThrowsAndMovesNothing() throws {
        let p = persistence()
        var s = try p.load(now: t0)
        try buildHistory(&s, from: t0)
        p.record(s); p.flush()
        try FileManager.default.removeItem(at: p.genesisURL)
        let garbage = Data("not json".utf8)
        try garbage.write(to: p.storeURL)

        XCTAssertThrowsError(try persistence().load(now: t0 + 100)) { e in
            XCTAssertEqual(e as? PersistenceError, .noGenesis)
        }
        XCTAssertEqual(try Data(contentsOf: p.storeURL), garbage)
        XCTAssertEqual(JSONLines.read(LogEntry.self, from: p.patchLogURL).values, s.patchLog)
    }

    func testDebouncedSnapshotsCoalesce() throws {
        let p = persistence(debounce: 0.25)
        var s = try p.load(now: t0)
        let writesAfterLoad = p.snapshotWrites
        for i in 0..<10 {
            try s.apply([.add("n\(i)", under: s.rootID)], author: .man, now: t0 + Double(i))
            p.record(s)
        }
        p.flush()
        XCTAssertEqual(p.snapshotWrites - writesAfterLoad, 1)
        XCTAssertEqual(JSONLines.read(LogEntry.self, from: p.patchLogURL).values.count, 10)
        XCTAssertEqual(try persistence().load(now: t0 + 100), s)
    }

    func systemLog() -> [SystemLogRecord] {
        JSONLines.read(SystemLogRecord.self, from: dir.appendingPathComponent("system-log.jsonl")).values
    }
}
