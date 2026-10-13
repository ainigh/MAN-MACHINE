# 07 — Model turns

**Goal.** The model is consulted once per round, at the boundary, with a deadline, and its output is
held until STRATEGY. SPEC §4, §5.2–5.4, §7, §8, §9.

## Deliverables (`Sources/MachinePromptsMan/Host/Model/`)
- `ModelAdapter` protocol: `func complete(_ prompt: String, deadline: Date) async throws -> String`.
  Two adapters: `OllamaAdapter` (http://127.0.0.1:11434, `/api/generate`, streaming off) and
  `AnthropicAdapter` (Messages API, key from Keychain, model from settings). `NullAdapter` returns
  nothing and is the default when none is configured (SPEC §9.4: a valid configuration).
- `PromptTemplate.swift`: the fixed template per SPEC §9.1, short, with one worked example, plus the
  session sentence. Store it as a resource string; version it in the turn log.
- `TurnEngine` (actor): `run(trigger:, store snapshot:, deadline:)` → projection → prompt → adapter →
  `EnvelopeParser.parse` → optional repair pass if `settings.repairPass` and time remains →
  validate the patch with `Store.apply` on a copy as `.model` (SPEC §5.4) → `TurnResult`.
  Logs everything to `turn-log.jsonl` (SPEC §12), including the ladder step and whether the deadline was met.
- `ModelTurnCoordinator` (`@MainActor`): on `.startModelTurn(deadline:)` starts one turn with
  `.phase`; on completion before the deadline appends the envelope to `store.held`; after the deadline
  applies SPEC §16 #17 (say dropped, ask dropped, patch kept as a proposal with `stale` recomputed on
  show). On `.renderHeld` moves `held` to the session pane's card and creates `Proposal`s in
  `store.pending`. On `.expireProposals` clears `pending` without writing `declined` (SPEC §16 #16).
  `message` and `answer` triggers run only in STRATEGY or with no session (SPEC §8.1); otherwise
  queued and run at the next STRATEGY.
- Proposal disposition in the UI (graph ghosts from 05 + the held card from 04): Accept all / per op /
  Reject. Reject writes `Declined` (summary derived from ops, TTL from settings). "Lock" promotes to
  `no_suggest`. Stale proposals per SPEC §5.3.
- Pending question (`ask`): shown in the held card with a text field; the reply becomes an `answer` turn.
- Settings: adapter choice, model name, endpoint, API key (Keychain), repair pass toggle, context note.

## Acceptance
- Tests with a `FakeAdapter`: (a) answers in time → held → rendered at STRATEGY; (b) answers late →
  say dropped, patch pending next round; (c) never answers → nothing happens, session unaffected,
  one turn-log line with `deadline_met: false`; (d) returns prose only → ladder step 5, `say` shown;
  (e) returns a patch touching a `no_suggest` node → whole patch rejected, reason logged, say still shown.
- Invariant #11 asserted in `SessionController`: a `startModelTurn` in a silent state is a programming
  error (`precondition`), never reachable from tests.
