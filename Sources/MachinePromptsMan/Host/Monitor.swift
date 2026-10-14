import Foundation
import Observation
import MpmCore

/// The parts of the running app the monitor draws. A picture of the host, not of the protocol: the
/// engine, the store and the model boundary are shown as the host meets them.
public enum Component: String, CaseIterable, Sendable, Hashable {
    case man, engine, timers, store, disk, coordinator, model, scheduler, output

    public var title: String {
        switch self {
        case .man: return "You"
        case .engine: return "Session engine"
        case .timers: return "Timers"
        case .store: return "Store"
        case .disk: return "Disk"
        case .coordinator: return "Turns"
        case .model: return "Model"
        case .scheduler: return "Initiative"
        case .output: return "Screen and sound"
        }
    }
}

public enum Outcome: String, Sendable, Comparable {
    case info, ok, warning, error

    private var rank: Int { switch self { case .info: 0; case .ok: 1; case .warning: 2; case .error: 3 } }
    public static func < (a: Outcome, b: Outcome) -> Bool { a.rank < b.rank }
}

/// One thing that happened: a hand-off between two components (`to` set) or work inside one (`to` nil).
public struct MonitorEvent: Identifiable, Equatable, Sendable {
    public let id: Int
    /// Engine time, as the logs record it.
    public let at: Date
    /// Real time, for motion: in test mode engine time runs 60× and would rush every pulse.
    public let real: Date
    public let from: Component
    public let to: Component?
    public let outcome: Outcome
    public let title: String
    public let detail: String
    public let turnID: String?

    public func touches(_ c: Component) -> Bool { from == c || to == c }
}

/// Work in progress inside a component. `deadline` is real time, when the work has one (a model turn).
public struct MonitorActivity: Equatable, Sendable {
    public var label: String
    public var since: Date
    public var deadline: Date?
}

/// The fixed diagram: where each component sits (unit square, origin top left) and which hand-offs
/// exist. Every pair the host emits is an edge here; `MonitorTests` holds the host to that.
public enum MonitorLayout {
    public static let position: [Component: (x: Double, y: Double)] = [
        .timers: (0.36, 0.14), .output: (0.64, 0.14),
        .man: (0.08, 0.46), .engine: (0.36, 0.46), .coordinator: (0.64, 0.46), .model: (0.92, 0.46),
        .store: (0.36, 0.82), .disk: (0.64, 0.82), .scheduler: (0.92, 0.82),
    ]

    public struct Edge: Hashable, Sendable {
        public let a: Component
        public let b: Component
        public init(_ a: Component, _ b: Component) { self.a = a; self.b = b }
        public func joins(_ x: Component, _ y: Component) -> Bool { (a == x && b == y) || (a == y && b == x) }
    }

    public static let edges: [Edge] = [
        Edge(.man, .engine), Edge(.timers, .engine), Edge(.engine, .output), Edge(.engine, .coordinator),
        Edge(.man, .store), Edge(.engine, .store), Edge(.coordinator, .store), Edge(.store, .disk),
        Edge(.coordinator, .model), Edge(.scheduler, .coordinator), Edge(.coordinator, .output),
    ]

    public static func edge(_ from: Component, _ to: Component) -> Edge? {
        edges.first { $0.joins(from, to) }
    }
}

/// The live picture behind the monitor panel. A view of what the SPEC §12 logs record, held in memory
/// only: it is never persisted and never projected to the model (SPEC §13 #8).
@MainActor
@Observable
public final class Monitor {
    public private(set) var events: [MonitorEvent] = []
    public private(set) var activity: [Component: MonitorActivity] = [:]
    /// Errors and warnings not yet looked at, per component. Cleared by `acknowledge`.
    public private(set) var unseen: [Component: Outcome] = [:]
    public private(set) var unseenCount: [Component: Int] = [:]

    public static let limit = 500

    @ObservationIgnored private let realNow: () -> Date
    @ObservationIgnored private var nextID = 0

    public init(realNow: @escaping () -> Date = { Date() }) {
        self.realNow = realNow
    }

    @discardableResult
    public func emit(_ from: Component, to: Component? = nil, _ outcome: Outcome, _ title: String,
                     detail: String = "", turnID: String? = nil, at: Date) -> MonitorEvent {
        nextID += 1
        let e = MonitorEvent(id: nextID, at: at, real: realNow(), from: from, to: to, outcome: outcome,
                             title: title, detail: detail, turnID: turnID)
        events.append(e)
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
        if outcome >= .warning {
            // The receiving end is where the failure shows: a refused patch is the store's, a failed turn the model's.
            let owner = outcome == .error ? (to ?? from) : from
            unseen[owner] = max(unseen[owner] ?? .info, outcome)
            unseenCount[owner, default: 0] += 1
        }
        return e
    }

    public func begin(_ c: Component, _ label: String, deadline: Date? = nil) {
        activity[c] = MonitorActivity(label: label, since: realNow(), deadline: deadline)
    }

    public func end(_ c: Component) {
        activity[c] = nil
    }

    public func acknowledge(_ c: Component? = nil) {
        if let c { unseen[c] = nil; unseenCount[c] = nil } else { unseen = [:]; unseenCount = [:] }
    }

    public var unseenTotal: Int { unseenCount.values.reduce(0, +) }
    public var worstUnseen: Outcome? { unseen.values.max() }

    public func events(touching c: Component) -> [MonitorEvent] { events.filter { $0.touches(c) } }

    /// The outcome of the latest non-info event that involved `c`, for its status dot.
    public func lastOutcome(_ c: Component) -> Outcome? {
        events.last { $0.touches(c) && $0.outcome != .info }?.outcome
    }

    /// Hand-offs still travelling along their edge at real time `now`, oldest first, with progress 0…1.
    public func inFlight(now: Date, duration: TimeInterval) -> [(event: MonitorEvent, progress: Double)] {
        var out: [(MonitorEvent, Double)] = []
        for e in events.reversed() {
            let age = now.timeIntervalSince(e.real)
            if age > duration { break }
            guard e.to != nil, age >= 0 else { continue }
            out.append((e, age / duration))
        }
        return out.reversed()
    }

    // MARK: Wording for engine traffic (SPEC §6.5, §6.9)

    static func describe(_ e: Event) -> String {
        switch e {
        case .startSession: return "start_session"
        case .commit: return "commit"
        case .finish: return "finish"
        case .snooze: return "snooze"
        case .stop: return "stop"
        case .endSession: return "end_session"
        case .tick(let k): return "tick \(describe(k))"
        case .activity(let idle): return idle ? "activity: idle" : "activity: active"
        }
    }

    static func describe(_ k: TimerKind) -> String {
        switch k {
        case .reminder(let t): return "reminder at \(Announcement.fmt(t))"
        case .roundEnd: return "round end"
        case .grace: return "grace"
        case .snoozeEnd: return "snooze end"
        case .statusEnd: return "status end"
        case .strategyEnd: return "strategy end"
        case .breakEnd: return "break end"
        }
    }

    /// Refusals are the engine saying no; everything else it announces is the session working as designed.
    static func outcome(_ a: Announcement) -> Outcome {
        switch a {
        case .refused, .notAvailable: return .warning
        default: return .info
        }
    }
}

extension Monitor {
    /// Disk reports arrive from the persistence queue, after the change that caused them.
    func disk(_ e: DiskEvent, at: Date) {
        switch e {
        case .patchLogAppended(let n):
            emit(.store, to: .disk, .ok, "patch log: \(n) entr\(n == 1 ? "y" : "ies") appended", at: at)
        case .snapshotWritten(let v):
            end(.disk)
            emit(.store, to: .disk, .ok, "snapshot written at version \(v)", at: at)
        case .failed(let reason):
            end(.disk)
            emit(.store, to: .disk, .error, "write failed", detail: reason, at: at)
        }
    }
}
