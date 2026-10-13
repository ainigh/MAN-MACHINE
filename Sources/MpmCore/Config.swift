import Foundation

/// SPEC §6.1 — the five session parameters. All times in seconds.
public struct SessionConfig: Codable, Equatable, Sendable {
    public var R: TimeInterval   // round length
    public var r: Int            // reminders per round
    public var Ls: TimeInterval  // sitting limit
    public var Lb: TimeInterval  // movement break
    public var G: TimeInterval   // grace window at time-up

    public init(R: TimeInterval, r: Int, Ls: TimeInterval, Lb: TimeInterval, G: TimeInterval = 10) {
        self.R = R; self.r = r; self.Ls = Ls; self.Lb = Lb; self.G = G
    }

    /// SPEC §16 #1–2. Ls and Lb are placeholders until set from health guidance.
    public static let `default` = SessionConfig(R: 600, r: 3, Ls: 45 * 60, Lb: 3 * 60, G: 10)

    public enum ConfigError: Error, Equatable, CustomStringConvertible {
        case roundTooShort, remindersBelowOne, sittingLimitNotAboveRound, breakNotPositive, graceNotPositive
        public var description: String {
            switch self {
            case .roundTooShort: return "R must be greater than 1 minute"
            case .remindersBelowOne: return "r must be at least 1"
            case .sittingLimitNotAboveRound: return "Ls must be greater than R"
            case .breakNotPositive: return "Lb must be positive"
            case .graceNotPositive: return "G must be positive"
            }
        }
    }

    public func validate() throws {
        if R <= 60 { throw ConfigError.roundTooShort }
        if r < 1 { throw ConfigError.remindersBelowOne }
        if Ls <= R { throw ConfigError.sittingLimitNotAboveRound }
        if Lb <= 0 { throw ConfigError.breakNotPositive }
        if G <= 0 { throw ConfigError.graceNotPositive }
    }

    // MARK: Derived (SPEC §6.2). Frozen for 2.x.

    /// q = R / 2^r
    public var q: TimeInterval { R / pow(2.0, Double(r)) }

    /// Zmax = r
    public var zMax: Int { r }

    /// Time *remaining* at which each reminder fires, descending.
    /// max(60 s, R / 2^k) for k = 1..r, de-duplicated after the clamp.
    public var reminders: [TimeInterval] {
        var out: [TimeInterval] = []
        for k in 1...r {
            let v = max(60, R / pow(2.0, Double(k)))
            if out.last != v { out.append(v) }
        }
        return out
    }

    /// STATUS length = q · 2^(z+1) / (x + 1)
    public func statusLength(z: Int, x: Int) -> TimeInterval {
        q * pow(2.0, Double(z + 1)) / Double(x + 1)
    }

    public var snoozeLength: TimeInterval { q }
    public var strategyLength: TimeInterval { q }
}
