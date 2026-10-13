import Foundation

/// A scheduled callback that can be called off. Cancelling after it fired is a no-op.
@MainActor
public protocol Cancellable: AnyObject {
    func cancel()
}

/// The host owns time (CLAUDE.md hard rule 2). The engine only ever sees `now()` values passed in.
@MainActor
public protocol Clock: AnyObject {
    func now() -> Date
    func schedule(at date: Date, _ f: @escaping @MainActor @Sendable () -> Void) -> Cancellable
}

/// Wall-clock time. Timers use `DispatchWallTime` so a sleeping Mac does not stretch them;
/// on wake the controller sweeps anything that came due (tasks/02).
public final class SystemClock: Clock {
    public init() {}

    public func now() -> Date { Date() }

    public func schedule(at date: Date, _ f: @escaping @MainActor @Sendable () -> Void) -> Cancellable {
        let token = Token()
        let delay = max(0, date.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + delay) { [weak token] in
            MainActor.assumeIsolated {
                guard let token, !token.cancelled else { return }
                token.cancelled = true
                f()
            }
        }
        return token
    }

    final class Token: Cancellable {
        var cancelled = false
        func cancel() { cancelled = true }
    }
}

/// A timeline that runs `factor` times faster than `real`, starting at `base`. Used for test mode (60×)
/// and, with factor 1, to keep engine time continuous after test mode is switched off mid-session.
public final class ScaledClock: Clock {
    public let factor: Double
    public let base: Date
    private let realBase: Date
    private let real: Clock

    public init(factor: Double, base: Date, real: Clock = SystemClock()) {
        precondition(factor > 0)
        self.factor = factor
        self.base = base
        self.real = real
        self.realBase = real.now()
    }

    public func now() -> Date { base.addingTimeInterval(real.now().timeIntervalSince(realBase) * factor) }

    public func schedule(at date: Date, _ f: @escaping @MainActor @Sendable () -> Void) -> Cancellable {
        real.schedule(at: realBase.addingTimeInterval(date.timeIntervalSince(base) / factor), f)
    }
}

/// A clock that only moves when told to. Fires due callbacks in time order, each at its own instant.
public final class ManualClock: Clock {
    private var current: Date
    private var items: [(id: Int, at: Date, f: @MainActor @Sendable () -> Void)] = []
    private var nextID = 0

    public init(_ start: Date) { current = start }

    public func now() -> Date { current }

    public func schedule(at date: Date, _ f: @escaping @MainActor @Sendable () -> Void) -> Cancellable {
        nextID += 1
        items.append((nextID, date, f))
        return Token(id: nextID, clock: self)
    }

    public var pendingCount: Int { items.count }

    /// Moves to `date`, firing everything due on the way. A callback may schedule more; those fire too if due.
    public func advance(to date: Date) {
        while let i = items.indices.min(by: { (items[$0].at, items[$0].id) < (items[$1].at, items[$1].id) }),
              items[i].at <= date {
            let item = items.remove(at: i)
            current = max(current, item.at)
            item.f()
        }
        current = max(current, date)
    }

    public func advance(by seconds: TimeInterval) { advance(to: current.addingTimeInterval(seconds)) }

    /// Jumps without firing anything, as a sleeping machine does. Pair with the controller's wake sweep.
    public func jump(to date: Date) { current = date }

    fileprivate func remove(_ id: Int) { items.removeAll { $0.id == id } }

    final class Token: Cancellable {
        let id: Int
        weak var clock: ManualClock?
        init(id: Int, clock: ManualClock) { self.id = id; self.clock = clock }
        func cancel() { clock?.remove(id) }
    }
}
