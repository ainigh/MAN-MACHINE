import Foundation
import MpmCore

/// What the controller tells the model side. The engine emits these effects; the host does exactly
/// these and nothing more (CLAUDE.md hard rule 3). Implemented for real by `ModelTurnCoordinator` (task 07).
@MainActor
public protocol ModelTurnCoordinating: AnyObject {
    /// SPEC §8.1 `phase` trigger, once per round at STATUS entry. The turn must be over by `deadline`.
    func startPhaseTurn(deadline: Date)
    /// SPEC §8.6: STRATEGY started; move held output to the screen.
    func renderHeld()
    /// SPEC §8.5 / §16 #16: commit happened; pending proposals expire without being declined.
    func expireProposals()
    func sessionEnded()
}

/// Records calls and does nothing else. The "no model" configuration is valid (SPEC §9.4).
public final class RecordingCoordinator: ModelTurnCoordinating {
    public enum Call: Equatable { case startPhaseTurn(Date), renderHeld, expireProposals, sessionEnded }
    public private(set) var calls: [Call] = []
    public init() {}
    public func startPhaseTurn(deadline: Date) { calls.append(.startPhaseTurn(deadline)) }
    public func renderHeld() { calls.append(.renderHeld) }
    public func expireProposals() { calls.append(.expireProposals) }
    public func sessionEnded() { calls.append(.sessionEnded) }
}
