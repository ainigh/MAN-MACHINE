import Foundation

// Public constructors for core value types the host needs to build. Additions only: nothing about
// these types changes (CLAUDE.md, "You may add to MpmCore"). A same-signature public init would clash
// with the synthesized internal one, hence factories.

extension RuleHit {
    public static func hit(_ rule: String, _ nodeID: NodeID) -> RuleHit {
        RuleHit(rule: rule, nodeID: nodeID)
    }
}
