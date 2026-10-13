import XCTest
@testable import MpmCore

final class ConfigTests: XCTestCase {
    func testDerivedFromProtocolWorkedExample() {
        // SPEC Protocol §9.1: R = 10 min, r = 3
        let c = SessionConfig(R: 600, r: 3, Ls: 2700, Lb: 180)
        XCTAssertEqual(c.q, 75)
        XCTAssertEqual(c.zMax, 3)
        XCTAssertEqual(c.reminders, [300, 150, 75])
        XCTAssertEqual(c.statusLength(z: 0, x: 1), 75)
        XCTAssertEqual(c.statusLength(z: 0, x: 0), 150)
        XCTAssertEqual(c.statusLength(z: 1, x: 1), 150)
        XCTAssertEqual(c.statusLength(z: 3, x: 0), 1200)   // 20 min
        XCTAssertEqual(c.statusLength(z: 0, x: 2), 50, accuracy: 0.001)
        XCTAssertEqual(c.statusLength(z: 2, x: 3), 150)
    }

    func testReminderClampingTable() {
        // Protocol §9.2
        XCTAssertEqual(SessionConfig(R: 600, r: 4, Ls: 2700, Lb: 180).reminders, [300, 150, 75, 60])
        XCTAssertEqual(SessionConfig(R: 300, r: 3, Ls: 2700, Lb: 180).reminders, [150, 75, 60])
        XCTAssertEqual(SessionConfig(R: 240, r: 4, Ls: 2700, Lb: 180).reminders, [120, 60])   // three merged
        // q unaffected by clamping
        XCTAssertEqual(SessionConfig(R: 240, r: 4, Ls: 2700, Lb: 180).q, 15)
    }

    func testValidation() {
        XCTAssertNoThrow(try SessionConfig.default.validate())
        XCTAssertThrowsError(try SessionConfig(R: 60, r: 3, Ls: 2700, Lb: 180).validate())
        XCTAssertThrowsError(try SessionConfig(R: 600, r: 0, Ls: 2700, Lb: 180).validate())
        XCTAssertThrowsError(try SessionConfig(R: 600, r: 3, Ls: 600, Lb: 180).validate())
        XCTAssertThrowsError(try SessionConfig(R: 600, r: 3, Ls: 2700, Lb: 0).validate())
    }

    func testFormat() {
        XCTAssertEqual(Announcement.fmt(45), "45 s")
        XCTAssertEqual(Announcement.fmt(90), "1:30")
        XCTAssertEqual(Announcement.fmt(600), "10 min")
        XCTAssertEqual(Announcement.fmt(3900), "1:05:00")
    }
}
