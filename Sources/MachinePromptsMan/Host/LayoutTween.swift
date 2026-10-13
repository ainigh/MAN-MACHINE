import Foundation
#if canImport(CoreGraphics)
import CoreGraphics   // CGRect/CGPoint members live here on Apple platforms
#endif

/// DESIGN §5: the graph's only spring (response 0.4, damping 0.85), evaluated by the view each frame
/// while a layout change settles. Pure.
public enum Spring {
    public static let response = 0.4
    public static let damping = 0.85
    /// Settled enough to stop animating.
    public static let duration = 1.0

    /// Fraction of the way from start to target at time `t` seconds (underdamped; 0 at t = 0, → 1).
    public static func progress(_ t: Double, response: Double = response, damping z: Double = damping) -> Double {
        guard t > 0 else { return 0 }
        guard t < duration else { return 1 }
        let w = 2 * Double.pi / response
        let wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * t) * (cos(wd * t) + z / (1 - z * z).squareRoot() * sin(wd * t))
    }
}

/// Positions moving from one layout to the next. New nodes start at their parent's current place,
/// so they grow out of it rather than appearing from nowhere.
public struct LayoutTween: Equatable, Sendable {
    public var from: [String: CGPoint] = [:]
    public var to: [String: CGPoint] = [:]
    public var start: Date = .distantPast
    /// With Reduce Motion the layout jumps (the view cross-fades instead).
    public var instant = false

    public init() {}

    public func position(_ id: String, at now: Date) -> CGPoint? {
        guard let target = to[id] else { return nil }
        guard !instant, let origin = from[id] else { return target }
        let p = Spring.progress(now.timeIntervalSince(start))
        return CGPoint(x: origin.x + (target.x - origin.x) * p, y: origin.y + (target.y - origin.y) * p)
    }

    public func animating(at now: Date) -> Bool { !instant && now.timeIntervalSince(start) < Spring.duration }

    /// Retargets from wherever things are now. `parents` maps a new id to its parent, for its start point.
    public mutating func retarget(_ targets: [String: CGPoint], parents: [String: String], now: Date, instant: Bool) {
        var current: [String: CGPoint] = [:]
        for id in to.keys { current[id] = position(id, at: now) }
        var newFrom: [String: CGPoint] = [:]
        for (id, _) in targets {
            if let c = current[id] { newFrom[id] = c }
            else if let p = parents[id], let pc = current[p] ?? targets[p] { newFrom[id] = pc }
        }
        from = newFrom
        to = targets
        start = now
        self.instant = instant
    }
}
