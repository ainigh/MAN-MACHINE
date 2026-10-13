import XCTest
import MpmCore
@testable import MpmHost

final class PresentationTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func sim() -> (Simulator, [String: NodeID]) {
        var settings = Settings.default
        settings.session = SessionConfig(R: 360, r: 3, Ls: 900, Lb: 120)
        var store = Store(rootTitle: "GOAL", now: t0, settings: settings, rootID: "root")
        var ids: [String: NodeID] = [:]
        for (i, name) in ["n1", "n2", "n3", "n4"].enumerated() {
            ids[name] = try! store.apply([.add(name, under: "root", tmp: name)], author: .man,
                                         now: t0.addingTimeInterval(Double(i))).entry.assignedIDs[name]!
        }
        return (Simulator(store: store, now: t0), ids)
    }

    func testCountdownDigitsRoundUpAndKeepTheirWidth() {
        XCTAssertEqual(Countdown.digits(600), "10:00")
        XCTAssertEqual(Countdown.digits(599.4), "10:00")
        XCTAssertEqual(Countdown.digits(599), "9:59")
        XCTAssertEqual(Countdown.digits(272), "4:32")
        XCTAssertEqual(Countdown.digits(0.2), "0:01")
        XCTAssertEqual(Countdown.digits(0), "0:00")
        XCTAssertEqual(Countdown.digits(-3), "0:00")
        XCTAssertEqual(Countdown.digits(20 * 60), "20:00")
        XCTAssertLessThanOrEqual(Countdown.digits(99 * 60 + 59).count, Countdown.reservedDigits.count)
    }

    func testMenuBarGlyphPerState() throws {
        var (s, id) = sim()
        XCTAssertEqual(MenuBarDisplay.make(s.store.session, now: s.now), MenuBarDisplay(glyph: .square, tone: .neutral, digits: nil))
        s.send(.startSession)
        XCTAssertEqual(MenuBarDisplay.make(s.store.session, now: s.now).glyph, .square)
        s.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        s.advance(360 - 272)
        let work = MenuBarDisplay.make(s.store.session, now: s.now)
        XCTAssertEqual(work.digits, "4:32")
        XCTAssertEqual(work.tone, .doing)
        XCTAssertEqual(work.glyph, .ring(272.0 / 360.0))
        s.advance(until: .timeUp); s.send(.stop)
        XCTAssertEqual(MenuBarDisplay.make(s.store.session, now: s.now).tone, .neutral)   // STATUS
        s.advance(until: .strategy)
        s.send(.commit(doing: id["n1"]!, next: id["n2"]!))   // seated 6:00+1:30+ → 15 min limit not hit
        s.advance(until: .timeUp); s.send(.stop); s.advance(until: .strategy)
        s.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        XCTAssertEqual(s.state, .break)
        let brk = MenuBarDisplay.make(s.store.session, now: s.now)
        XCTAssertEqual(brk.glyph, .dot); XCTAssertEqual(brk.tone, .rest); XCTAssertEqual(brk.digits, "2:00")
    }

    func testRingAndDigitsAgreeToTheSecond() throws {
        var (s, id) = sim()
        s.send(.startSession); s.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        for step in stride(from: 0.0, to: 360.0, by: 7.3) {
            let now = t0.addingTimeInterval(step)
            let session = s.store.session!
            let shown = Double(Countdown.seconds(Phase.remaining(session, now: now)))
            XCTAssertEqual(Phase.fraction(session, now: now, continuous: false), shown / 360, accuracy: 1e-12)
        }
    }

    func testControlsAreExactlyThePermittedEvents() throws {
        var (s, id) = sim()
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls, [.startSession])
        s.send(.startSession)
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls, [.commit, .endSession])
        s.send(.commit(doing: id["n1"]!, next: id["n2"]!))
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls, [.finish, .endSession])
        s.advance(until: .timeUp)
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls,
                       [.snooze(length: 45, left: 3), .stop, .endSession])
        s.send(.snooze)
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls, [.finish, .endSession])
        s.advance(until: .timeUp)
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls.first, .snooze(length: 45, left: 2))
        try s.patch([.setStatus(id["n1"]!, .done)])
        s.send(.stop)
        let status = SessionPaneDisplay.make(s.store, now: s.now)
        XCTAssertEqual(status.controls, [.endSession])
        XCTAssertEqual(status.awayFor, 90)                 // z 1, x 1 → 45·4/2
        XCTAssertEqual(status.diff.map(\.title), ["n1", "n2"])
        s.advance(until: .strategy)
        XCTAssertEqual(SessionPaneDisplay.make(s.store, now: s.now).controls, [.commit, .endSession])
    }

    func testCommitCheckUsesTheEngine() throws {
        var (s, id) = sim()
        XCTAssertEqual(CommitCheck.evaluate(doing: id["n1"], next: nil, store: s.store), .incomplete)
        XCTAssertEqual(CommitCheck.evaluate(doing: id["n1"], next: id["n2"], store: s.store), .ready)
        XCTAssertEqual(CommitCheck.evaluate(doing: id["n1"], next: id["n1"], store: s.store),
                       .refused("\(ValidationError.depOnSelf(id["n1"]!))"))
        try s.patch([.setStatus(id["n3"]!, .done)])
        if case .refused = CommitCheck.evaluate(doing: id["n3"], next: id["n2"], store: s.store) {} else { XCTFail() }
    }
}

final class ConfigReadoutTests: XCTestCase {
    func testFourMinuteRoundWithFourReminders() {
        // tasks/09 acceptance, matching ConfigTests.testReminderClampingTable.
        let r = ConfigReadout.make(SessionConfig(R: 240, r: 4, Ls: 2700, Lb: 180))
        XCTAssertEqual(r.reminders, ["2:00", "1:00"])
        XCTAssertEqual(r.merged, 3)
        XCTAssertEqual(r.q, 15)
        XCTAssertNil(r.error)
    }

    func testStatusTableAndValidation() {
        let r = ConfigReadout.make(SessionConfig.default)
        XCTAssertEqual(r.statusTable.count, 4)
        XCTAssertEqual(r.statusTable[0][1], 75)
        XCTAssertEqual(r.statusTable[3][0], 1200)
        XCTAssertNil(r.merged)
        XCTAssertEqual(ConfigReadout.make(SessionConfig(R: 600, r: 3, Ls: 600, Lb: 180)).error, "Ls must be greater than R")
    }
}

final class UpdaterLogicTests: XCTestCase {
    func testVersionOrder() {
        XCTAssertTrue(Version.isNewer("v0.0.12", than: "v0.0.9"))
        XCTAssertFalse(Version.isNewer("v0.0.9", than: "v0.0.12"))
        XCTAssertFalse(Version.isNewer("v0.0.3", than: "0.0.3"))
        XCTAssertTrue(Version.isNewer("v1.0.0", than: "0.9.9-4-gabc123"))
        XCTAssertFalse(Version.isNewer("v9.9.9", than: "dev"))
    }

    func testReleaseParsing() {
        let json = Data(#"{"tag_name":"v0.0.7","assets":[{"name":"other.txt","url":"x","browser_download_url":"y"},{"name":"MachinePromptsMan.zip","url":"https://api.github.com/repos/a/b/releases/assets/1","browser_download_url":"https://github.com/a/b/releases/download/v0.0.7/MachinePromptsMan.zip"}]}"#.utf8)
        let r = Release.parse(json)
        XCTAssertEqual(r?.tag, "v0.0.7")
        XCTAssertEqual(r?.assetAPIURL, "https://api.github.com/repos/a/b/releases/assets/1")
        XCTAssertNil(Release.parse(Data(#"{"tag_name":"v1","assets":[]}"#.utf8)))
    }
}

@MainActor
final class TestModeAutoOffTests: XCTestCase {
    func testTestModeSwitchesItselfOffAfterTheLimitInRealTime() async throws {
        let real = ManualClock(Date(timeIntervalSince1970: 1_800_000_000))
        let c = SessionController(store: Store(now: real.now()), clock: real)
        c.setTestMode(true, autoOffAfter: 30 * 60)
        real.advance(by: 30 * 60 - 1)
        XCTAssertTrue(c.testMode)
        real.advance(by: 2)
        XCTAssertFalse(c.testMode)
    }
}
