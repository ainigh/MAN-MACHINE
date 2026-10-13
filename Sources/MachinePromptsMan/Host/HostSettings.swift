import Foundation
import MpmCore

/// Settings the host owns that the core `Settings` does not carry (it is frozen with the store schema).
/// Stored in host-settings.json beside the store. Missing keys decode to defaults, so the file can grow.
public struct HostSettings: Codable, Equatable, Sendable {
    public var model = ModelSettings()
    /// DESIGN §10: one setting mutes every sound.
    public var muted = false
    /// SPEC §8.2: initiative rules can be switched off one by one.
    public var disabledRules: Set<String> = []
    /// SPEC §8.3 attention snooze for the whole system.
    public var snoozedUntil: Date?
    public var snoozedUntilNextSession = false
    /// SPEC §8.3 attention snooze per node.
    public var nodeSnoozes: [NodeID: Date] = [:]
    /// "rule|node" → when it was last nudged, so a standing hit nudges once per local day (tasks/08).
    public var lastNudged: [String: Date] = [:]
    public var turnLogDays = 90
    public var systemLogDays = 30
    /// tasks/10: test mode switches itself off after this long.
    public var testModeLimitMinutes = 30
    /// tasks/11: the notification permission is asked once, at the first reminder.
    public var askedForNotifications = false

    public init() {}

    public var retention: Retention { Retention(turnLogDays: turnLogDays, systemLogDays: systemLogDays) }

    enum CodingKeys: String, CodingKey {
        case model, muted, disabledRules, snoozedUntil, snoozedUntilNextSession, nodeSnoozes, lastNudged,
             turnLogDays, systemLogDays, testModeLimitMinutes, askedForNotifications
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HostSettings()
        model = try c.decodeIfPresent(ModelSettings.self, forKey: .model) ?? d.model
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? d.muted
        disabledRules = try c.decodeIfPresent(Set<String>.self, forKey: .disabledRules) ?? d.disabledRules
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        snoozedUntilNextSession = try c.decodeIfPresent(Bool.self, forKey: .snoozedUntilNextSession) ?? d.snoozedUntilNextSession
        nodeSnoozes = try c.decodeIfPresent([NodeID: Date].self, forKey: .nodeSnoozes) ?? d.nodeSnoozes
        lastNudged = try c.decodeIfPresent([String: Date].self, forKey: .lastNudged) ?? d.lastNudged
        turnLogDays = try c.decodeIfPresent(Int.self, forKey: .turnLogDays) ?? d.turnLogDays
        systemLogDays = try c.decodeIfPresent(Int.self, forKey: .systemLogDays) ?? d.systemLogDays
        testModeLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .testModeLimitMinutes) ?? d.testModeLimitMinutes
        askedForNotifications = try c.decodeIfPresent(Bool.self, forKey: .askedForNotifications) ?? d.askedForNotifications
    }
}

extension Persistence {
    public var hostSettingsURL: URL { directory.appendingPathComponent("host-settings.json") }

    public func loadHostSettings() -> HostSettings {
        guard let data = try? Data(contentsOf: hostSettingsURL),
              let s = try? JSONDecoder().decode(HostSettings.self, from: data) else { return HostSettings() }
        return s
    }

    public func saveHostSettings(_ s: HostSettings) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try AtomicFile.write(try Persistence.snapshotEncoder().encode(s), to: hostSettingsURL)
        } catch {
            appendSystem(SystemLogRecord(at: Date(), kind: .persistence, message: "host settings write failed: \(error)"))
        }
    }

    /// Turn-log lines, for the daily nudge budget (SPEC §8.3: counted from the turn log).
    public func readTurnLog() -> [TurnLogRecord] {
        flush()
        return JSONLines.read(TurnLogRecord.self, from: turnLogURL).values
    }

    /// Writes the whole store as JSON to `url` (tasks/09 export).
    public func export(_ store: Store, to url: URL) throws {
        try AtomicFile.write(try Persistence.snapshotEncoder().encode(store), to: url)
    }
}
