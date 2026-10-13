# CLAUDE.md — Machine-Prompts-Man

You are building a native macOS app from a finished specification. Read this file, then `SPEC.md`,
then `DESIGN.md`, then run `swift test`. Work through `tasks/` in order; each task says what done
means. Do not start a task until the one before it is merged and green.

## What this is

A timeboxed work companion. The human (Man) keeps a tree of work nodes. A deterministic **session
engine** runs rounds of work with reminders, a snooze budget, a status phase sized by how the round
went, a strategy phase, and a sitting limit. A language model is consulted **once per round, at the
boundary, and nowhere else**. The core protocol lives in `Sources/MpmCore`; it is written, tested,
and frozen. Your job is the host: persistence, timers, the app shell, the views, the model adapters,
and the polish.

## The three documents

- `SPEC.md` is law. Section numbers in code comments (`SPEC §6.5`) point into it. When the spec and
  your intuition disagree, the spec wins; if the spec is silent, choose the simplest option, mark it
  `[default]` in a comment, and add a row to the "Defaults chosen" table in SPEC.md §16 in the same PR.
- `DESIGN.md` is the visual and interaction bar. It is not optional and it is not a style guide to
  interpret loosely; it lists concrete decisions.
- `tasks/NN-*.md` are the work, in order. Each has a goal, deliverables, and acceptance criteria.

## Frozen (do not touch without a written argument in the PR, and expect it to be refused)

- `Sources/MpmCore/Config.swift` formulas (SPEC §6.2)
- `Sources/MpmCore/Engine.swift` transition table (SPEC §6.5)
- `Sources/MpmCore/Envelope.swift` the four keys (SPEC §4)
- The invariants in SPEC §13 and the tests in `Tests/MpmCoreTests/`

You may add to MpmCore (new pure functions, new tests). You may not change what existing tests assert.
If a host need seems to require a core change, write the need down in `tasks/OPEN.md` and build around it.

## Hard rules

1. **MpmCore imports only Foundation.** No AppKit, SwiftUI, Combine, os.log, or third-party packages
   in `Sources/MpmCore`. It must build and test on Linux (`swift test` in CI runs on both).
2. **The engine never touches a clock.** Every time is passed in as `now: Date`. The host owns timers.
   Timers are scheduled from `Effect.schedule` and cancelled from `Effect.cancelTimers`; nothing else.
3. **The model is silent during work.** No model call may be started in WORK, TIME_UP, SNOOZE or BREAK.
   Model output is rendered only in STRATEGY or when no session is running. The engine emits
   `.startModelTurn` and `.renderHeld`; the host does exactly those and nothing more.
4. **A model that never answers must leave a working app.** Every model call has a deadline; a missed
   deadline is logged and ignored. Test this path, not just the happy path.
5. **The human owns the graph.** Model patches are proposals shown for disposition. Man patches apply
   immediately. Nothing applies without going through `Engine.applyPatch` / `Store.apply`.
6. **Announcements are engine strings** (`Announcement.text`). Do not reword them in the UI; style them.
7. **Every state change is logged.** Patch log (in the store), turn log, system log. See SPEC §12.
8. **No cheese.** No emoji in the UI, no confetti, no gamification, no "You've got this!". The app is
   quiet, exact and beautiful. If a detail would look at home in a to-do app's onboarding, remove it.

## How to work

- One task per PR. Branch `task/NN-short-name`. The PR description quotes the task's acceptance
  criteria and ticks each one with evidence (a test name, a screenshot, a log line).
- Tests first for anything in MpmCore or the host engine. For views, a screenshot per state in the PR
  (light and dark) and a short screen recording of the motion for anything animated.
- `swift test` must pass on every push. CI builds a universal binary on `main`.
- Keep files small and named for what they contain. Mirror the layering: `Sources/MpmCore` (pure),
  `Sources/MachinePromptsMan/Host` (timers, persistence, adapters), `Sources/MachinePromptsMan/UI`
  (views only). A view never calls `Store.apply` directly; it sends an intent to the controller.
- Swift 6 language mode, strict concurrency. The controller is a `@MainActor` class; the store is a
  value type it owns. Adapters are `actor`s.
- Comments explain *why* and cite the spec section. No narration of *what* the code does.
- Do not add dependencies without listing them in the PR with a one-line reason. Prefer none.
- When something in a task is unclear, make the smallest reasonable choice, note it in the PR, and
  carry on. Do not stop to ask unless the choice would be expensive to reverse.

## Useful entry points

- `Simulator` (MpmCore): drives the engine on a virtual clock. The host's timer loop must produce the
  same effects in the same order; `IllustratedSessionTests` is the reference transcript.
- `Projection.project` and `EnvelopeParser.parse`: the model boundary, both pure.
- `Store.apply` returns an `ApplyResult` with the log entry and any nodes unblocked by the patch.

## Reference implementation to borrow from (patterns, not code)

The author has a working macOS menu-bar app (ask for its path) that already solved: ad-hoc signing and
the permissions dance, a menu-bar countdown, cards that stay until dismissed, a 60× test clock, quiet
mode, self-update from GitHub, frameless glass panels, and TTS via FluidAudio. Borrow the approach
to each where a task names it. Do not copy its visual style: this app has its own (DESIGN.md).

## Kickoff

```
Read CLAUDE.md, SPEC.md, DESIGN.md. Run `swift test`. Then open tasks/00-bootstrap.md and begin.
```
