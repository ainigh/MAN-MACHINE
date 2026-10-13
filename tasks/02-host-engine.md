# 02 — Host engine: clock, timers, controller

**Goal.** `Engine` effects become real timers and the app has one `@MainActor` controller that owns
the store. The 60× test clock exists from day one. SPEC §6, §8.6, §13 #10–12.

## Deliverables (`Sources/MachinePromptsMan/Host/`)
- `Clock` protocol: `now() -> Date`, `schedule(at: Date, _ f: @escaping () -> Void) -> Cancellable`.
  Two implementations: `SystemClock` and `ScaledClock(factor: 60, base: Date)` for test mode.
  Scaled time is a separate timeline that starts when test mode is turned on and is discarded when it
  ends (borrow the reference app's approach: planned timers are recomputed from real time).
- `SessionController` (`@MainActor`, `ObservableObject` or `@Observable`):
  - `private(set) var store: Store`
  - `func send(_ e: Event)` → `Engine.handle` → applies effects: schedules/cancels timers via `Clock`,
    appends announcements to `announcements: [Announcement]` (bounded to 50), publishes
    `lastAnnouncement`, posts `startModelTurn` / `renderHeld` / `expireProposals` / `sessionEnded`
    to a `ModelTurnCoordinator` stub (task 07) and to persistence.
  - `func apply(_ ops: [Op], author: Author) throws -> ApplyResult` → `Engine.applyPatch`, same effect handling.
  - `func undo()` / `redo()` through the patch log (redo = reapply the undone entry's `ops` as system).
  - Timer bookkeeping: one `Cancellable` per `TimerKind`; `cancelTimers` cancels all; a tick whose
    timer was cancelled must never reach the engine (guard with a generation counter).
  - `seatedNow: TimeInterval` and `remainingInPhase: TimeInterval` computed properties for the UI.
- Sleep/wake: on wake, compare `phaseEnd` with now; fire every timer that is due, in order (the
  engine handles stale ticks). Reminders missed during sleep are announced once, not each.
- System log: every `Effect` and every transition written as a line.

## Acceptance
- `HostEngineTests`: using `ScaledClock` with factor 600, replay the illustrated session and assert the
  controller's announcement list equals `IllustratedSessionTests`' transcript, ignoring timestamps.
- A cancelled timer's tick never reaches the engine (test with a timer cancelled 1 ms before due).
- Turning test mode off mid-round re-plans the phase end from real time without changing the state.

## Out of scope
Any UI, any model call (the coordinator is a stub that records calls).
