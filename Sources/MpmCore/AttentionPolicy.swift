import Foundation

/// SPEC §8.3. Decides whether a `schedule` or `initiative` trigger may wake the model now. Pure.
/// `phase` triggers never pass through here: they are part of the session Man chose to run.
public enum AttentionPolicy {

    public enum Decision: Equatable, Sendable {
        case run
        case `defer`(until: Date, reason: String)
        /// Held until the session ends (schedule) or folded into the next phase projection (initiative).
        case deferToSessionEnd
        case suppress(reason: String)
    }

    public struct Context: Equatable, Sendable {
        public var sessionActive: Bool
        /// System-wide attention snooze (not the session snooze).
        public var snoozedUntil: Date?
        /// Snoozed "until the next session": nothing runs until a session has started.
        public var snoozedUntilNextSession: Bool
        /// Turns from `schedule` and `initiative` triggers already run on the local day of `now`.
        public var nudgesToday: Int
        public init(sessionActive: Bool = false, snoozedUntil: Date? = nil, snoozedUntilNextSession: Bool = false, nudgesToday: Int = 0) {
            self.sessionActive = sessionActive; self.snoozedUntil = snoozedUntil
            self.snoozedUntilNextSession = snoozedUntilNextSession; self.nudgesToday = nudgesToday
        }
    }

    /// Order in which rule hits are worth a nudge when the budget is tight ("highest-priority rule first").
    public static let rulePriority = ["overdue", "unblocked", "due_soon", "stale", "drift"]

    public static func decide(now: Date, settings: Settings, context: Context) -> Decision {
        if context.sessionActive { return .deferToSessionEnd }
        if context.snoozedUntilNextSession { return .suppress(reason: "snoozed until the next session") }
        if let until = context.snoozedUntil, until > now { return .defer(until: until, reason: "snoozed") }
        if let end = quietHoursEnd(containing: now, settings: settings) { return .defer(until: end, reason: "quiet hours") }
        if context.nudgesToday >= settings.maxNudgesPerDay {
            return .defer(until: startOfNextDay(after: now, settings: settings), reason: "daily budget of \(settings.maxNudgesPerDay) used")
        }
        return .run
    }

    /// The end of the quiet-hours window `now` falls in, or nil when outside it. Handles windows across midnight.
    public static func quietHoursEnd(containing now: Date, settings: Settings) -> Date? {
        let cal = calendar(settings)
        let start = settings.quietHoursStart, end = settings.quietHoursEnd
        guard start != end else { return nil }
        let hour = cal.component(.hour, from: now)
        let inside = start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
        guard inside else { return nil }
        let todayEnd = cal.date(bySettingHour: end, minute: 0, second: 0, of: now)!
        return todayEnd > now ? todayEnd : cal.date(byAdding: .day, value: 1, to: todayEnd)!
    }

    public static func startOfNextDay(after now: Date, settings: Settings) -> Date {
        let cal = calendar(settings)
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
    }

    public static func sameLocalDay(_ a: Date, _ b: Date, settings: Settings) -> Bool {
        calendar(settings).isDate(a, inSameDayAs: b)
    }

    /// SPEC §8.3 model `next`. In a session: no earlier than the next STRATEGY start. Outside: within
    /// [min_interval, max_interval] of now. Quiet hours and the budget still apply when it fires.
    public static func clampNext(_ requested: Date, now: Date, settings: Settings,
                                 sessionActive: Bool, nextStrategyStart: Date?) -> Date {
        if sessionActive {
            return max(requested, nextStrategyStart ?? now)
        }
        let lo = now.addingTimeInterval(Double(settings.minModelIntervalMinutes) * 60)
        let hi = now.addingTimeInterval(Double(settings.maxModelIntervalHours) * 3600)
        return min(max(requested, lo), hi)
    }

    /// SPEC §8.3 coalescing: several pending initiative triggers become one, each hit once, highest priority first.
    public static func coalesce(_ batches: [[RuleHit]]) -> [RuleHit] {
        var seen = Set<String>(); var out: [RuleHit] = []
        for h in batches.flatMap({ $0 }) where seen.insert(h.rule + "|" + h.nodeID).inserted { out.append(h) }
        func rank(_ r: String) -> Int { rulePriority.firstIndex(of: r) ?? rulePriority.count }
        return out.enumerated().sorted { (rank($0.element.rule), $0.offset) < (rank($1.element.rule), $1.offset) }.map(\.element)
    }

    static func calendar(_ settings: Settings) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: settings.timezone) ?? .current
        return cal
    }
}
