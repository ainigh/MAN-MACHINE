import XCTest
@testable import MpmCore

final class AttentionPolicyTests: XCTestCase {
    var settings: Settings = {
        var s = Settings.default
        s.timezone = "Europe/London"
        s.quietHoursStart = 22; s.quietHoursEnd = 8; s.maxNudgesPerDay = 3
        return s
    }()

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal.date(from: c)!
    }

    func testQuietHoursDeferToTheWindowEnd() {
        XCTAssertEqual(AttentionPolicy.decide(now: at(2026, 10, 14, 23, 30), settings: settings, context: .init()),
                       .defer(until: at(2026, 10, 15, 8), reason: "quiet hours"))
        XCTAssertEqual(AttentionPolicy.decide(now: at(2026, 10, 15, 6), settings: settings, context: .init()),
                       .defer(until: at(2026, 10, 15, 8), reason: "quiet hours"))
        XCTAssertEqual(AttentionPolicy.decide(now: at(2026, 10, 15, 8), settings: settings, context: .init()), .run)
        var day = settings; day.quietHoursStart = 12; day.quietHoursEnd = 14
        XCTAssertEqual(AttentionPolicy.decide(now: at(2026, 10, 15, 13), settings: day, context: .init()),
                       .defer(until: at(2026, 10, 15, 14), reason: "quiet hours"))
    }

    func testBudgetExhaustedDefersToTomorrow() {
        let d = AttentionPolicy.decide(now: at(2026, 10, 15, 15), settings: settings, context: .init(nudgesToday: 3))
        XCTAssertEqual(d, .defer(until: at(2026, 10, 16, 0), reason: "daily budget of 3 used"))
        XCTAssertEqual(AttentionPolicy.decide(now: at(2026, 10, 15, 15), settings: settings, context: .init(nudgesToday: 2)), .run)
    }

    func testSessionAndSnoozeComeFirst() {
        let noon = at(2026, 10, 15, 12)
        XCTAssertEqual(AttentionPolicy.decide(now: noon, settings: settings, context: .init(sessionActive: true)), .deferToSessionEnd)
        XCTAssertEqual(AttentionPolicy.decide(now: noon, settings: settings, context: .init(snoozedUntil: at(2026, 10, 15, 13))),
                       .defer(until: at(2026, 10, 15, 13), reason: "snoozed"))
        if case .suppress = AttentionPolicy.decide(now: noon, settings: settings, context: .init(snoozedUntilNextSession: true)) {} else { XCTFail() }
    }

    func testNextInsideASessionClampsToTheNextStrategy() {
        let now = at(2026, 10, 15, 12)
        let strategy = now.addingTimeInterval(400)
        XCTAssertEqual(AttentionPolicy.clampNext(now.addingTimeInterval(30), now: now, settings: settings,
                                                 sessionActive: true, nextStrategyStart: strategy), strategy)
        let later = now.addingTimeInterval(3600)
        XCTAssertEqual(AttentionPolicy.clampNext(later, now: now, settings: settings, sessionActive: true, nextStrategyStart: strategy), later)
        // Outside a session: within [30 min, 72 h].
        XCTAssertEqual(AttentionPolicy.clampNext(now.addingTimeInterval(60), now: now, settings: settings,
                                                 sessionActive: false, nextStrategyStart: nil), now.addingTimeInterval(1800))
        XCTAssertEqual(AttentionPolicy.clampNext(now.addingTimeInterval(1e7), now: now, settings: settings,
                                                 sessionActive: false, nextStrategyStart: nil), now.addingTimeInterval(72 * 3600))
    }

    func testTwoInitiativeTriggersCoalesce() {
        let a = [RuleHit(rule: "due_soon", nodeID: "n2"), RuleHit(rule: "overdue", nodeID: "n1")]
        let b = [RuleHit(rule: "overdue", nodeID: "n1"), RuleHit(rule: "stale", nodeID: "n3")]
        XCTAssertEqual(AttentionPolicy.coalesce([a, b]).map { "\($0.rule) \($0.nodeID)" },
                       ["overdue n1", "due_soon n2", "stale n3"])
    }
}
