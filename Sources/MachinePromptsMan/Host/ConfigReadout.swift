import Foundation
import MpmCore

/// tasks/09: the live read-out under the session settings. Values come from `SessionConfig`'s frozen
/// formulas (SPEC §6.2); this only arranges them.
public struct ConfigReadout: Equatable, Sendable {
    public var q: TimeInterval
    public var zMax: Int
    /// Time remaining at each reminder, descending, as the countdown shows it ("2:00").
    public var reminders: [String]
    /// How many reminder values the one-minute clamp folded into the last one, if more than one.
    public var merged: Int?
    /// Status length by z (rows, 0…Zmax) and x (columns, 0…3).
    public var statusTable: [[TimeInterval]]
    public var error: String?

    public static let xColumns = 0...3

    public static func make(_ c: SessionConfig) -> ConfigReadout {
        var problem: String?
        do { try c.validate() } catch { problem = "\(error)" }
        guard c.r >= 1, c.R > 0 else {
            return ConfigReadout(q: 0, zMax: max(0, c.r), reminders: [], merged: nil, statusTable: [], error: problem)
        }
        let rems = c.reminders
        let mergedCount = c.r - rems.count + 1
        return ConfigReadout(
            q: c.q, zMax: c.zMax, reminders: rems.map(Countdown.digits),
            merged: mergedCount > 1 ? mergedCount : nil,
            statusTable: (0...c.zMax).map { z in xColumns.map { x in c.statusLength(z: z, x: x) } },
            error: problem)
    }
}
