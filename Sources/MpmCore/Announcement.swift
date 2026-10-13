import Foundation

/// SPEC §6.9. Fixed wording, emitted by the engine, never by the model.
public enum Announcement: Equatable, Sendable {
    case sessionOpen
    case roundStart(round: Int, doing: String?, next: String?, R: TimeInterval)
    case reminder(remaining: TimeInterval)
    case timesUp
    case snoozeAccepted(z: Int, zMax: Int, length: TimeInterval)
    case noSnoozesLeft
    case stop
    case tooLate
    case statusStart(roundElapsed: TimeInterval, length: TimeInterval, z: Int, x: Int, diff: [DiffLine])
    case strategyStart(length: TimeInterval)
    case autoCommit(doing: String?, next: String?)
    case nowDoing(String)
    case noDoingNode
    case noOpenNodes
    case movementBreak(seated: TimeInterval, length: TimeInterval)
    case `continue`(seated: TimeInterval)
    case sittingClockReset
    case notAvailable
    case refused(String)

    public var text: String {
        switch self {
        case .sessionOpen: return "Session open. Commit to start."
        case .roundStart(let k, let d, let n, let R):
            return "Round \(k). \(d ?? "nothing") doing, \(n ?? "nothing") next. \(Announcement.fmt(R)), starting now."
        case .reminder(let t): return "\(Announcement.fmt(t)) left."
        case .timesUp: return "Time's up."
        case .snoozeAccepted(let z, let zMax, let q): return "Snooze \(z) of \(zMax). \(Announcement.fmt(q))."
        case .noSnoozesLeft: return "No snoozes left. Stop."
        case .stop: return "Stop."
        case .tooLate: return "Too late. Stop."
        case .statusStart(let el, let len, _, _, let diff):
            var s = "Round over at \(Announcement.fmt(el)). Status, \(Announcement.fmt(len))."
            if !diff.isEmpty { s += " " + diff.map { "\($0.title) \($0.from.rawValue)→\($0.to.rawValue)" }.joined(separator: ", ") + "." }
            return s
        case .strategyStart(let q): return "Strategy, \(Announcement.fmt(q))."
        case .autoCommit(let d, let n): return "No choice made. \(d ?? "nothing") doing, \(n ?? "nothing") next."
        case .nowDoing(let t): return "Now doing \(t)."
        case .noDoingNode: return "No doing node."
        case .noOpenNodes: return "No open nodes."
        case .movementBreak(let s, let lb): return "Seated \(Announcement.fmt(s)). Movement break, \(Announcement.fmt(lb))."
        case .continue(let s): return "Seated \(Announcement.fmt(s)). Continue."
        case .sittingClockReset: return "Sitting clock reset."
        case .notAvailable: return "Not available now."
        case .refused(let why): return "Refused: \(why)."
        }
    }

    /// 45 s → "45 s", 90 s → "1:30", 600 s → "10 min", 3900 s → "1:05:00"
    public static func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s < 60 { return "\(s) s" }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        if sec == 0 { return "\(m) min" }
        return String(format: "%d:%02d", m, sec)
    }
}
