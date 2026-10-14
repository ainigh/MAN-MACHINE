import Foundation
import MpmCore

public struct TurnRequest: Sendable {
    public var turnID: String
    public var trigger: Trigger
    /// The store as it was when the trigger was accepted. The model sees only its projection (SPEC §13 #8).
    public var store: Store
    /// Engine time at the trigger.
    public var now: Date
    public var hits: [RuleHit]
    /// Real time by which the turn must be over.
    public var realDeadline: Date
    public var contextNote: String
}

public struct TurnResult: Sendable, Equatable {
    public var turnID: String
    public var projection: String
    public var prompt: String
    public var raw: String?
    public var repaired: Bool
    public var step: ParseStep?
    public var warnings: [String]
    /// nil when the turn failed or the model returned nothing.
    public var envelope: Envelope?
    /// The SPEC §5.4 reason the patch was rejected, if it was.
    public var validation: String?
    public var error: String?
    public var latency: TimeInterval
}

/// SPEC §8.7 steps 3–7: projection, prompt, adapter, parse (with the optional repair pass), validate.
/// Never touches the live store; the coordinator decides what to do with the result.
public actor TurnEngine {
    private let adapter: ModelAdapter
    private let realNow: @Sendable () -> Date

    public init(adapter: ModelAdapter, realNow: @escaping @Sendable () -> Date = { Date() }) {
        self.adapter = adapter
        self.realNow = realNow
    }

    public func run(_ r: TurnRequest) async -> TurnResult {
        let started = realNow()
        let inSession = r.store.session.map { $0.state != .end } ?? false
        let projection = Projection.project(r.store, trigger: r.trigger, now: r.now, hits: r.hits)
        let prompt = PromptTemplate.render(projection: projection, inSession: inSession, contextNote: r.contextNote)
        var result = TurnResult(turnID: r.turnID, projection: projection, prompt: prompt, raw: nil, repaired: false,
                                step: nil, warnings: [], envelope: nil, validation: nil, error: nil, latency: 0)

        let raw: String
        do {
            raw = try await adapter.complete(prompt, deadline: r.realDeadline)
        } catch {
            result.error = error is CancellationError ? "cancelled" : "\(error)"
            result.latency = realNow().timeIntervalSince(started)
            return result
        }
        result.raw = raw
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.latency = realNow().timeIntervalSince(started)
            return result
        }

        let first = EnvelopeParser.parse(raw)
        var outcome = (envelope: first.envelope, step: first.step, warnings: first.warnings)
        if outcome.step.rawValue > ParseStep.braceSubstring.rawValue, r.store.settings.repairPass,
           realNow() < r.realDeadline, !Task.isCancelled {
            // SPEC §9.3: one repair pass when steps 1–3 failed and the deadline allows; if it fails too, prose only.
            result.repaired = true
            if let raw2 = try? await adapter.complete(PromptTemplate.repair(raw: raw), deadline: r.realDeadline) {
                let o2 = EnvelopeParser.parse(raw2)
                outcome = o2.step.rawValue <= ParseStep.braceSubstring.rawValue ? (o2.envelope, o2.step, o2.warnings) : Self.proseOnly(raw)
            } else {
                outcome = Self.proseOnly(raw)
            }
        }
        result.step = outcome.step
        result.warnings = outcome.warnings
        var env = outcome.envelope
        let (kept, rejection) = Self.validate(env.patch, against: r.store, now: r.now)
        env.patch = kept
        result.validation = rejection
        result.envelope = env
        result.latency = realNow().timeIntervalSince(started)
        return result
    }

    static func proseOnly(_ raw: String) -> (envelope: Envelope, step: ParseStep, warnings: [String]) {
        (Envelope(say: raw.trimmingCharacters(in: .whitespacesAndNewlines)), .proseOnly, [])
    }

    /// SPEC §5.4 on a copy, as `model`. Whole-patch rejection unless `lenient_validation` is on, in which case
    /// only the offending ops are dropped. Returns the ops kept and the reason for any rejection.
    static func validate(_ ops: [Op], against store: Store, now: Date) -> ([Op], String?) {
        guard !ops.isEmpty else { return ([], nil) }
        var copy = store
        do {
            try copy.apply(ops, author: .model, now: now)
            return (ops, nil)
        } catch {
            guard store.settings.lenientValidation else { return ([], "\(error)") }
            var kept: [Op] = []; var reasons: [String] = []
            for op in ops {
                var trial = copy
                do { try trial.apply(kept + [op], author: .model, now: now); kept.append(op) }
                catch { reasons.append("\(error)") }
            }
            return (kept, reasons.joined(separator: "; "))
        }
    }
}
