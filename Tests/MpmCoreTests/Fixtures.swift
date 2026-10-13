import Foundation
@testable import MpmCore

enum Fixtures {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A store with the illustrated session's starting map: n1..n4 open under the root.
    static func starting(config: SessionConfig = SessionConfig(R: 360, r: 3, Ls: 900, Lb: 120)) -> (Store, [String: NodeID]) {
        var settings = Settings.default
        settings.session = config
        var store = Store(rootTitle: "GOAL", now: t0, settings: settings, rootID: "root")
        var ids: [String: NodeID] = [:]
        for (i, name) in ["n1", "n2", "n3", "n4"].enumerated() {
            let r = try! store.apply([.add(name, under: "root", tmp: name)], author: .man,
                                     now: t0.addingTimeInterval(Double(i)))   // distinct createdAt, in order
            ids[name] = r.entry.assignedIDs[name]!
        }
        return (store, ids)
    }
}
