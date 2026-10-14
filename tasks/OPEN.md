# Open questions and core-change requests

Append here when a task needs something the frozen core does not offer. Each entry: task, what is
needed, why it cannot be done in the host, proposed spec change. The author decides.

## 1. Context note and invariant #8 (task 07)

- **Need.** Task 07 asks for a "context note" in the model settings. SPEC §13 #8 says nothing reaches
  the model that is not in `project(store, trigger)`.
- **What the host does.** The note is rendered as one line of the prompt template ("About this
  person: …"), not of the projection. The template is fixed per spec version except for this line,
  and the template version is in every turn-log line.
- **Proposed.** SPEC §9.1: "The template may carry one user-written sentence about the person,
  shown in Settings and logged with the template version." Or drop the note.

## 2. Host-only settings outside `Settings` (tasks 07–10)

- **Need.** Adapter choice, attention snooze, rules on/off, per-node snoozes, mute, retention, the
  once-per-day nudge memory.
- **Why not in the core.** `Settings` is part of the store's Codable schema and frozen with it.
  Adding fields changes decoding of existing stores.
- **What the host does.** `host-settings.json` beside the store, decoding missing keys to defaults.
- **Proposed.** None needed now. If the spec wants these in the store, a 2.x minor could add
  optional `Settings` fields with tolerant decoding.

## 3. Public constructors on core value types

- **Need.** The host builds `RuleHit` values (the `unblocked` initiative from patch results).
- **Why.** A public struct's memberwise initializer is internal.
- **What the host does.** Added `RuleHit.hit(_:_:)` in `Sources/MpmCore/PublicInits.swift`: an
  addition, nothing existing changed. `ParseOutcome` has the same gap; the turn engine works around it.
- **Proposed.** Public memberwise initializers on core value types in a future pass.
