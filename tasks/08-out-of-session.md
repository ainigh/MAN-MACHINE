# 08 — Outside a session: initiative, schedule, attention policy

**Goal.** When no session is running, the machine still prompts the man, within policy. SPEC §8.2–8.5.

## Deliverables
- `InitiativeScheduler` (Host): every 15 minutes and at launch, `InitiativeRules.evaluate`; if there
  are hits and no session, build one `initiative` trigger with all hits (coalescing) and pass it
  through `AttentionPolicy`.
- `AttentionPolicy` (MpmCore, pure, with tests): quiet hours, daily budget (count turns per local
  day from the turn log), system snooze (`snoozedUntil` in settings), model `next` clamping to
  `[minModelInterval, maxModelInterval]` and to after session end / next STRATEGY (SPEC §8.3).
  Returns `.run | .defer(until:) | .suppress(reason:)`; every decision goes to the system log.
- `ScheduleEntry` firing: a timer per entry; `source: model` entries come from `next`.
- Schedule view (DESIGN: a simple list): upcoming entries, rules on/off, snooze the system for
  1 h / until tomorrow / until the next session.
- Out-of-session model output renders in the session pane's held card immediately (no session means no silence rule).

## Acceptance
- `AttentionPolicyTests`: quiet hours defer to the window end; budget exhausted defers to tomorrow;
  `next` inside a session clamps to the next STRATEGY; two initiative triggers within a minute coalesce.
- Launching the app with an overdue node and no session shows one nudge, once per day.
