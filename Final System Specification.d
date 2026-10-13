# Machine-Prompts-Man: System Specification

**Version:** 2.0
**Status:** Design spec, ready to build. Implementation language, UI framework and hosting are out of scope and live in a separate document.
**Supersedes:** 1.0 (sealed). Section 18 lists every breaking change.

---

## 0. Purpose

A system in which the machine initiates interaction with the human, rather than waiting to be asked. The human keeps a structured plan (a tree of work nodes) and works through it in timeboxed rounds. A deterministic **session engine** keeps the clock, gives reminders, enforces snooze limits, and sizes the pauses between rounds from how each round went. A **model** is consulted once per round, at the boundary, and only there.

Design goals, in priority order:

1. **Simple.** Few moving parts, each with one job.
2. **Effective.** Timing is exact, nudges are timely, and nothing interrupts a round.
3. **Closed for modification, open for extension.** The core protocol is sealed. New capability comes from outside the core, never from widening the protocol.
4. **Model agnostic.** Any LLM, including weak ones, must work with degraded but safe behaviour. A model that never answers must still leave a working system.
5. **Inspectable.** Every state change, every clock event and every model exchange is logged.

---

## 1. Principles

- **The graph is the memory.** There is no conversation history. The model's only memory of the past is what has been written into the graph.
- **The human owns the graph.** Model changes are always proposals. Human changes apply immediately.
- **Script does mechanics, model does judgement.** Timing, triggering, validation, persistence, scheduling and projection are deterministic code. Phrasing, prioritisation and suggestions are the model's.
- **Script keeps time. The model never does.** Every reminder, phase length, snooze count and break is a function of the clock, the configuration and the log. The model has no clock authority.
- **The model is silent during work.** It receives one turn per round, at the round boundary, and its output is shown only in the strategy phase. Nothing it does can interrupt a round.
- **The model never sees the whole store.** It sees a projection, computed by a pure function.
- **Four verbs, forever.** The model's output vocabulary is `say`, `ask`, `patch`, `next`. See §4.
- **Notes live outside.** The system stores task structure, not task content. Content is a link to wherever the human keeps it.
- **Nodes are never deleted.** They are crossed out, so the history of the plan is preserved and the log stays replayable.

---

## 2. Vocabulary

| Term | Meaning |
|---|---|
| **Man** | The human. The Worker (B) in the protocol documents. |
| **Engine** | The session engine: deterministic script that keeps time. The Timekeeper (A) in the protocol documents. |
| **Model** | The LLM behind a model adapter. An advisor; never the timekeeper. |
| **Store** | Canonical state: nodes, patch log, session, and a small amount of system state. |
| **Node** | One task/step/topic in the graph. |
| **Graph** | The tree of nodes plus dependency edges. |
| **Slot** | One of the two session positions: **D** (doing) and **N** (next). Each is held by at most one node. |
| **Session** | A run of rounds between `start_session` and `end_session`. |
| **Round** | One pass through the cycle: Commit → Work → Status → Strategy → Sitting check. |
| **Phase** | One state of the engine within a round (§6.4). |
| **Projection** | The text the model receives, computed from the store. |
| **Patch** | An ordered list of ops that change the store. |
| **Proposal** | A patch authored by the model, awaiting human disposition. |
| **Trigger** | An event that starts a model turn. |
| **Turn** | One model cycle: trigger → projection → model → envelope → disposition. |
| **Envelope** | The parsed model output: the four verbs. |
| **Announcement** | A fixed-wording message emitted by the engine (§6.9). Not model output. |
| **Modality** | An input or output channel (keyboard, STT, screen, TTS). |
| **View** | A rendering of the store (grid, graph, session, settings, schedule). |

---

## 3. State

### 3.1 Node schema

```
Node {
  id          : string      // stable, opaque, never reused (ULID recommended)
  title       : string
  parent      : id | null   // null only for the root
  deps        : id[]        // "cannot start until these are done"
  status      : "open" | "doing" | "next" | "blocked" | "done" | "crossed_out"
  due         : date | null
  progress    : 0..100
  description : string      // short; one paragraph max
  links       : url[]       // where the real notes live
  ai_note     : string      // model's scratchpad for this node; model may patch
  flags       : string[]    // e.g. "no_suggest", "pinned"
  created_at  : datetime
  updated_at  : datetime    // set by script on every change to this node
}
```

Status meanings:

| Status | Meaning |
|---|---|
| `open` | Known work, not currently planned |
| `doing` | Holds slot D. The node being worked on now. |
| `next` | Holds slot N. The node expected after D. |
| `blocked` | Has an unfinished dependency. Set by script from `deps`; never set directly. |
| `done` | Cleared |
| `crossed_out` | Abandoned or no longer relevant; kept for history |

Rules:

- The graph is a **tree** via `parent`, with optional **dependency edges** via `deps`. Cycles in either are rejected.
- **At most one node is `doing` and at most one is `next`**, and they are distinct. Either slot may be vacant; §6.7 says how vacancies are filled.
- `blocked` is derived: a node is `blocked` while any node in `deps` is not `done`. When the last dep is cleared the script moves it to `open` and raises the `unblocked` initiative (§8.2). Human edits that would set `blocked` or set `open` on a node with unfinished deps are rejected.
- `links` is the extension point for notes. The system never fetches or parses link targets.
- `ai_note` is the only field intended for the model's own memory. Humans may read and clear it.
- `flags` is an open string set, but only these have system meaning:
  - `no_suggest` — model must not propose changes to this node or nudge about it.
  - `pinned` — always included in full in the projection.

### 3.2 Store

```
Store {
  schema_version : int          // 2
  version        : int          // increments on every applied patch
  nodes          : Node[]
  patch_log      : LogEntry[]   // append-only
  session        : Session | null
  pending        : Proposal[]
  question       : PendingQuestion | null
  held           : Envelope[]   // model output waiting for the next STRATEGY (§8.6)
  declined       : Declined[]
  settings       : Settings
  schedule       : ScheduleEntry[]
}
```

### 3.3 Patch log (event sourcing)

Every change to nodes is a patch, and every applied patch is appended:

```
LogEntry {
  seq        : int
  at         : datetime
  author     : "man" | "model" | "system"
  base       : int              // store.version before applying
  ops        : Op[]
  inverse    : Op[]             // computed by script at apply time
  turn_id    : string | null
  session_id : string | null    // set while a session is active
  round      : int | null       // round number within the session
}
```

Consequences:

- **Undo/redo** = apply `inverse` / reapply `ops`.
- **Persistence** = snapshot of `nodes` + the log. Rebuild is replay.
- **Audit** = the log.
- **Conflict detection** = `base` check (§5.3).
- **x is computed from the log** (§6.6). The human never reports it.

### 3.4 Small system state

```
Session         { id, started_at, state, round, round_start, z, x,
                  seated_s, sensor_inactive, timers }            // §6.3
Proposal        { id, turn_id, at, ops, say, expires_at }        // §5.2
PendingQuestion { turn_id, at, text, expires_at }                // §8.4
Declined        { node_id | null, summary, at, expires_at }      // §8.5
Settings        { session: SessionConfig, quiet_hours, max_nudges_per_day,
                  timezone, modality_policy, due_soon_days, stale_days,
                  drift_days, repair_pass, lenient_validation, ... }
SessionConfig   { R, r, Ls, Lb, G }                              // §6.1
ScheduleEntry   { id, at | cron, reason, source: "man" | "model" }
```

---

## 4. Sealed Verbs

**Directive: the model output vocabulary is exactly these four verbs. No verb may be added, removed or renamed. Any desired new capability must be expressed through these verbs, through the graph, or outside the system. This section is not subject to revision in 2.x.**

```
Envelope {
  say   : string            // prose for the human. May be empty.
  ask   : string | null     // a question that expects an answer.
  patch : Op[]              // proposed graph changes. May be empty.
  next  : datetime | null   // when the model wants to be woken again.
}
```

Semantics:

- **say** — rendered to the human via the output modality. Never changes state.
- **ask** — like `say`, but sets `store.question`. The next human message is routed as an *answer* (§8.4). At most one open question at a time.
- **patch** — becomes a **proposal**, never applied directly. Validated by script before it is shown (§5.4).
- **next** — creates a `ScheduleEntry` with `source: "model"`, subject to attention policy (§8.3). During a session it is clamped to the next STRATEGY start or to after session end.

**The session needs no fifth verb.** A commit is a patch that sets one node `doing` and one `next`. A suggestion to stop early is `say`. A request for the human's view is `ask`. The model has no way to start, pause, extend or end a round, and must not be given one.

What is deliberately *not* a verb: tool calls, modality selection, search, fetching links, sending messages to third parties, deleting the store, any clock operation.

---

## 5. Patch Protocol

### 5.1 Ops

```
add_node    { tmp_id, parent, title, status?, due?, progress?, description? }
update_node { id, fields: { ...subset of mutable fields... } }
move_node   { id, parent }
cross_out   { id }            // node and its unfinished descendants → crossed_out
restore     { id }            // crossed_out → open (one node, no cascade)
remove_node { id }            // man only; see below
add_dep     { id, dep }
remove_dep  { id, dep }
```

- `tmp_id` in `add_node` lets a single patch reference nodes it creates. Script assigns real ids on apply.
- `update_node` with `status: doing` or `status: next` **takes the slot**: any previous holder of that slot moves to `open` in the same patch (script appends the op, and its inverse). This is how commit works.
- `cross_out` cascades to descendants that are `open`, `doing`, `next` or `blocked` **[default]**. `done` descendants stay `done`.
- `remove_node` exists only for typo repair. Allowed for author `man`, on a leaf, that has never been `doing`, `next` or `done` according to the log. Everything else is crossed out, never removed.
- Mutable by anyone: `title, parent, deps, status, due, progress, description, links, flags`.
- Mutable by model only via proposal: all of the above plus `ai_note`.
- Never mutable by model: `id, created_at, updated_at`, and the `no_suggest` flag (model cannot remove it).
- `blocked` is never set by a patch; it is derived (§3.1).

### 5.2 Author rules

| Author | Applied when |
|---|---|
| man | Immediately, if valid. |
| model | Only when the human accepts the proposal (whole or per-op). |
| system | Immediately: `updated_at`, `blocked` derivation, slot displacement, vacancy promotion (§6.7), auto-commit (§6.7). |

A proposal is presented with its `say` text so the human sees the reasoning next to the change. During a session, proposals are shown only in STRATEGY and expire at commit (§8.6).

### 5.3 Base version and conflicts

Every patch carries `base`. On apply, if `base != store.version`:

- Author `man`: rebase if ops touch only nodes unchanged since `base`; otherwise reject and re-render.
- Author `model`: the proposal is marked **stale** and shown as such. Human may still accept op-by-op; stale ops that touch changed nodes are blocked.

### 5.4 Validation (script, before anything is shown or applied)

Reject the whole patch, with a logged reason, if any op:

- references an unknown id or an invalid parent;
- creates a `deps` cycle or a `parent` cycle;
- sets `blocked`, or sets `open` on a node with unfinished deps;
- would leave two nodes `doing` or two nodes `next` (cannot happen after slot displacement, but checked);
- sets the same node `doing` and `next`;
- sets `doing` on a `blocked`, `done` or `crossed_out` node;
- removes a node that is not a leaf, or has ever held a slot or been done, or is authored by model;
- touches a node flagged `no_suggest` (model author only);
- sets a field outside the mutable set for that author;
- exceeds limits: more than **N ops per patch** (default 12) or more than **M new nodes** (default 5);
- is not permitted in the current session state (§6.8).

Reject only the offending ops instead if `settings.lenient_validation` is on. Default is whole-patch rejection: predictable beats clever.

---

## 6. Session Engine

The engine is a deterministic state machine. Every decision it makes is a function of the clock, `SessionConfig`, the per-round counters, the sitting clock and the map. It never interprets the content of the work and never consults the model.

### 6.1 Configuration

| Name | Meaning | Constraint | Default |
|---|---|---|---|
| **R** | Round length | R > 1 min | 10 min |
| **r** | Reminders per round | r ≥ 1 | 3 |
| **Ls** | Sitting limit: max continuous seated time | Ls > R | 45 min **[default, set from health guidance]** |
| **Lb** | Movement break: min time away to reset the sitting clock | Lb > 0 | 3 min **[default, set from health guidance]** |
| **G** | Grace window to answer time-up | G > 0 | 10 s **[default]** |

### 6.2 Derived at session start

```
q          = R / 2^r                          base unit
Zmax       = r                                snoozes per round
reminders  = sorted, de-duplicated set of max(60 s, R / 2^k) for k = 1..r
             (each value is time remaining when the reminder fires)
```

The clamp guarantees the final reminder is at least one minute before time-up: a signal to get ready to stop. Clamping affects reminders only; q is unchanged.

Phase lengths:

| Phase | Length |
|---|---|
| One snooze | q |
| STATUS | q · 2^(z+1) / (x + 1) |
| STRATEGY | q |
| BREAK | Lb |

### 6.3 Session state

```
Session {
  id              : string
  started_at      : datetime
  state           : State                 // §6.4
  round           : int                   // 1-based
  round_start     : datetime              // when WORK was last entered
  z               : int                   // snoozes used this round
  x               : int | null            // nodes cleared, frozen at STATUS entry
  seated_s        : int                   // continuous seated time, seconds
  sensor_inactive : bool                  // from optional activity sensor
  timers          : { phase_end, reminders[] }
}
```

`z` and `x` reset when WORK is entered.

### 6.4 States

| State | Meaning | Duration |
|---|---|---|
| IDLE | Session open, waiting for the first commit | Unbounded |
| WORK | Round in progress | R |
| TIME_UP | Round time expired, waiting for snooze decision | G |
| SNOOZE | Extension | q |
| STATUS | Report plus away time | q · 2^(z+1) / (x + 1) |
| STRATEGY | Man chooses next D and N | q |
| SIT_CHECK | Instant decision | 0 |
| BREAK | Movement break | Lb |
| END | Session closed | — |

### 6.5 Events and transitions

**From Man:** `start_session`, `commit(D, N)`, `finish`, `snooze`, `stop`, patches, `end_session`
**From the system:** `tick` (timer expiry); optionally `activity(active | idle)` from a sensor

Naming note: the protocol documents call `finish` "done" and `stop` "decline". They are renamed here so that the event `finish` is never confused with the status `done`.

| From | Event | Guard | To | Actions |
|---|---|---|---|---|
| — | start_session | no session | IDLE | create Session |
| IDLE | commit(D, N) | valid (§6.5.1) | WORK | set slots; start round |
| WORK | tick (reminder) | — | WORK | announce time remaining |
| WORK | finish | — | STATUS | freeze x; compute length; start model turn (§8.1) |
| WORK | tick (R elapsed) | — | TIME_UP | announce "time's up" |
| TIME_UP | snooze | z < Zmax | SNOOZE | z += 1; announce |
| TIME_UP | snooze | z = Zmax | STATUS | announce "no snoozes left, stop"; freeze x |
| TIME_UP | stop | — | STATUS | announce "stop"; freeze x |
| TIME_UP | tick (G elapsed) | — | STATUS | treated as `stop` **[default]** |
| SNOOZE | finish | — | STATUS | freeze x |
| SNOOZE | tick (q elapsed) | — | TIME_UP | announce "time's up" |
| STATUS | tick (length elapsed) | — | STRATEGY | apply sitting reset (§6.6.2); render held model output (§8.6); show round diff |
| STRATEGY | commit(D, N) | valid | SIT_CHECK | set slots; expire pending proposals |
| STRATEGY | tick (q elapsed) | — | SIT_CHECK | auto-commit (§6.7); expire pending proposals |
| SIT_CHECK | — | seated_s + R > Ls | BREAK | announce break |
| SIT_CHECK | — | otherwise | WORK | start round |
| BREAK | tick (Lb elapsed) | — | WORK | seated_s = 0; start round |
| any | patch | allowed in state (§6.8) | same | apply; log; check vacancies (§6.7) |
| any | end_session | — | END | log; session = null |

"Start round" means: `round += 1`, `round_start = now`, `z = 0`, `x = null`, schedule reminders and the R timer, announce round start.

Notes:

- `commit` in STRATEGY is how strategy ends early. There is no `finish` for strategy.
- **STATUS cannot be ended early [default].** It is the cost of the round and the away time. This narrows Protocol §6 ("done ends any phase early"); the state-machine document is authoritative.
- **BREAK cannot be ended early.** It is a health limit.
- A `snooze` after the grace window is ignored with the announcement "too late, stop".
- A commit from the Graph or Grid view is one `man` patch setting `doing` and `next`; the engine treats a patch that fills both slots while in IDLE or STRATEGY as `commit`.

#### 6.5.1 Validity of commit(D, N)

D and N must exist, be distinct, and have status `open`, `doing` or `next`. D must not be `blocked` **[default; the protocol documents had no deps]**. N may be `blocked` only if its unfinished deps are exactly {D}. Otherwise the engine refuses with the reason and stays in the current state.

### 6.6 Computations

#### 6.6.1 x (nodes cleared)

At STATUS entry:

```
x = number of distinct nodes that
      (a) changed to done at some point in [round_start, now), per the patch log, and
      (b) are still done now
```

Includes **[default]**: child nodes at any depth; nodes added and cleared within the same round; nodes cleared during SNOOZE. Excludes crossed-out nodes and nodes marked done then reopened. Done-changes made during STATUS, STRATEGY or BREAK count toward no round.

#### 6.6.2 Sitting clock

```
seated_s accumulates in:  WORK, TIME_UP, SNOOZE, STATUS, STRATEGY
does not accumulate in:   IDLE, BREAK, END

at STATUS end:  if status length ≥ Lb and not sensor_inactive → seated_s = 0
at BREAK end:   seated_s = 0
in IDLE:        if idle duration ≥ Lb → seated_s = 0
at END:         seated_s discarded
```

Without a sensor the engine trusts that Man moved **[default]**. With a sensor, `sensor_inactive` is true if no movement was detected for the whole phase; a desk-input proxy (no keyboard or mouse input for the entire phase) is acceptable.

### 6.7 Vacancy rules [default]

| Situation | What the engine does |
|---|---|
| D becomes vacant during WORK or SNOOZE (done or crossed out) and no new `doing` was set in the same patch | Promote N to `doing` (system patch); announce "now doing n". Round continues. |
| D becomes vacant and N is also vacant | Round continues with no D; announce "no doing node". Man may set one or `finish`. |
| N becomes vacant during WORK, SNOOZE or STATUS | Leave vacant until STRATEGY. |
| STRATEGY ends without commit | Auto-commit (system patch): D = current N if set, else oldest `open` node; N = oldest `open` node ≠ D. Announce the result. |
| Auto-commit finds no `open` node | Go to IDLE; announce "no open nodes". |

"Oldest" means earliest `created_at`. The engine uses order, never content.

Marking D done does not end the round: Man keeps working on the promoted N, which is how x ≥ 2 happens. Man ends the round with `finish`.

### 6.8 Permissions by state

| State | commit | finish | snooze | stop | patch | end_session | model turn |
|---|---|---|---|---|---|---|---|
| IDLE | ✓ | | | | ✓ | ✓ | |
| WORK | | ✓ | | | ✓ | ✓ | |
| TIME_UP | | | ✓ | ✓ | ✓ | ✓ | |
| SNOOZE | | ✓ | | | ✓ | ✓ | |
| STATUS | | | | | ✓ | ✓ | started |
| STRATEGY | ✓ | | | | ✓ | ✓ | rendered; `answer` turns allowed |
| BREAK | | | | | | ✓ | |

Any other event is ignored with the announcement "not available now". Patches are blocked during BREAK **[default]** so the break stays away from the task. Man patches during STATUS are the status report: the engine shows the round diff automatically, so no separate reporting step exists.

### 6.9 Announcements

Fixed wording, emitted by the engine, rendered through the output modality. Never generated by the model.

| Trigger | Message |
|---|---|
| Session start | "Session open. Commit to start." |
| Round start | "Round k. n doing, m next. R, starting now." |
| Reminder | "T left." |
| R or snooze elapsed | "Time's up." |
| Snooze accepted | "Snooze z of Zmax. q." |
| Snooze refused | "No snoozes left. Stop." |
| Stop or grace timeout | "Stop." |
| Late snooze | "Too late. Stop." |
| STATUS start | "Round over at T. Status, L." followed by the round diff |
| STRATEGY start | "Strategy, q." followed by held model output, if any |
| Auto-commit | "No choice made. n doing, m next." |
| Vacancy promotion | "Now doing n." / "No doing node." |
| SIT_CHECK → BREAK | "Seated S. Movement break, Lb." |
| SIT_CHECK → WORK | "Seated S. Continue." |
| BREAK end | "Sitting clock reset." |
| Invalid event or patch | "Not available now." / reason |

---

## 7. Projection

`project(store, trigger) → string` is a **pure function**. It is the only thing the model sees, together with the fixed prompt template.

### 7.1 Contents, in order

1. Current datetime and timezone.
2. Trigger: kind and reason (§8.1), plus the human message if any.
3. **If a session is active:** round number, R, z, Zmax, x, status-phase length, seated time, and the round diff (nodes whose status changed in this round, one line each).
4. If a question is pending: the question text, marked as such.
5. Recently declined suggestions (§8.5), one line each.
6. Initiative rule hits suppressed during the session (§8.2), one line each.
7. The graph, rendered per §7.2.

### 7.2 Rendering rules

- `pinned`, `doing`, `next`, `blocked` and overdue nodes: full fields except `links`.
- `open` nodes: title, due, progress, one-line description.
- `done`/`crossed_out` subtrees: collapsed to `[done] <title> (n children)` / `[x] <title> (n children)`.
- `no_suggest` nodes: title only, marked `[locked]`.
- `description` truncated to a configurable length.
- `ai_note` included in full for any node rendered in full.
- Per-node freshness: `updated <n> days ago`. Never the raw log.
- Hard cap on total size; if exceeded, drop `open` nodes furthest from D and N first, then collapse deeper levels.

### 7.3 Format

Indented plain text with stable node ids visible:

```
session: round 3, R 10m, z 1/3, x 1, status 2m30s, seated 24m
round diff: n_01HZ open→done, n_01J0 blocked→open

[n_01HX...] Launch v2  (open, due 2026-11-01, 40%)
  [n_01HY...] Write spec  (done)
  [n_01HZ...] Build API  (done, updated 2m ago)
    note: user prefers to batch backend work on Fridays
  [n_01J0...] Design review  (next)
  [n_01J1...] Deploy  (doing, 10%)
```

Not JSON. Plain text projects better across models and is cheaper.

---

## 8. Turn Engine

### 8.1 Triggers

All turns start with exactly one trigger:

| Kind | Source | Reason field | Allowed during session |
|---|---|---|---|
| `message` | human typed/spoke | free text | STRATEGY, IDLE |
| `answer` | human replied while `question` pending | free text | STRATEGY, IDLE |
| `phase` | engine entered STATUS | round summary | STATUS only; exactly once per round |
| `schedule` | `ScheduleEntry` fired | `source` + `reason` | never; deferred to session end |
| `initiative` | initiative rule fired (§8.2) | rule name + node ids | never; folded into the next `phase` projection |

Triggers are serialised: one turn at a time. Triggers arriving during a turn queue; duplicate initiative triggers collapse. A `message` typed during WORK is applied as a quick-log patch if it parses as one, otherwise held and routed as a `message` trigger at the next STRATEGY.

### 8.2 Initiative rules (script, not model)

Deterministic rules decide *that* a nudge is warranted and *why*; the model decides *how to say it*. Initial rule set:

- `overdue` — `due < today` and status not done/crossed_out.
- `due_soon` — `due` within `settings.due_soon_days`.
- `stale` — `doing` or `next` and `updated_at` older than `settings.stale_days`.
- `unblocked` — a node whose deps all became done.
- `drift` — `progress` unchanged for `settings.drift_days` on a `doing` node.

During a session, rules are evaluated but never wake the model. Their hits appear in the `phase` projection so the model can mention them at the boundary. Rules are configurable and may be added without touching the protocol.

### 8.3 Attention policy (script)

Applied to every `schedule` and `initiative` trigger before it may wake the model:

- **Session**: suppressed entirely while a session is active (§8.1).
- **Quiet hours**: suppressed, deferred to end of window.
- **Daily budget**: `max_nudges_per_day`; excess deferred to next day, highest-priority rule first.
- **Snooze**: human can snooze a node or the whole system for a duration. This is the attention snooze; it is unrelated to the session snooze.
- **Model `next`**: clamped to `[min_interval, max_interval]` outside a session; during a session, clamped to the next STRATEGY start or to after session end. Cannot bypass quiet hours or budget.
- **Coalescing**: multiple pending initiative triggers merge into one turn with multiple reasons.

`phase` triggers are not subject to policy: they are part of the session Man chose to run.

### 8.4 Pending question

- `ask` sets `store.question` with an `expires_at` (default outside a session: next quiet-hours boundary; during a session: end of the next STRATEGY **[default]**).
- A human message while a question is pending is routed as an `answer` trigger, which includes the question text in the projection.
- Answer or expiry clears the slot. There is never more than one. This is the whole of multi-turn memory, by design.

### 8.5 Declined memory

- When a proposal is rejected, script writes a `Declined` entry: the node ids touched and a one-line summary (derived from the ops, not from the model), with a TTL (default 14 days).
- Proposals that **expire** at commit without disposition are not written as declined **[default]**: ignoring was always a legitimate response.
- The projection includes active entries so the model does not repeat itself.
- Human can promote a decline to a permanent `no_suggest` flag on the node.

### 8.6 Held output and the latency budget

During a session, model output is rendered only in STRATEGY.

- The `phase` turn starts at STATUS entry. Its deadline is STATUS end. Output arriving before the deadline is placed in `store.held`.
- At STRATEGY start, `held` is rendered, oldest first, then cleared. Proposals in it are shown for disposition.
- Output arriving after STRATEGY has ended is logged and discarded, except `ask`, which is dropped, and `patch`, which is kept as a pending proposal for the next STRATEGY **[default]**.
- `answer` and `message` turns started in STRATEGY render as soon as they arrive if still in STRATEGY; otherwise they go to `held`.
- Pending proposals not dispositioned by commit expire (§8.5).

A model that is slow or down costs the session nothing: the engine never waits for it.

### 8.7 Turn lifecycle

```
1. trigger accepted (policy passed, or kind = phase)
2. turn_id assigned; turn log opened; deadline set if in session
3. projection = project(store, trigger)
4. prompt = template + projection
5. raw = adapter.complete(prompt)
6. envelope = parse(raw)            // §9
7. validate(envelope.patch)         // §5.4
8. side effects:
     say   → render now, or hold (§8.6)
     ask   → set question, or hold
     patch → store.pending += proposal
     next  → schedule (policy-clamped)
9. turn log closed with outcome
```

A turn that fails at any step logs the failure and does nothing to the store. The human is told something went wrong only if the trigger was a `message` or `answer`.

---

## 9. Model Adapter

The single model-specific component. Interface:

```
complete(prompt: string) → raw: string
```

Everything else is shared script.

### 9.1 Prompt template

Fixed per spec version. Contains: role, the four verbs with one worked example, the projection, and the output format instruction. Must be short. No chain-of-thought instructions. During a session the role text adds one sentence: the model is an advisor consulted between rounds, it cannot change timing, and a commit is a patch setting one node `doing` and one `next`.

### 9.2 Output format

Preferred: a single fenced block containing JSON with the four keys. Prose outside the block is ignored.

```
```envelope
{"say":"...","ask":null,"patch":[],"next":null}
```
```

### 9.3 Degradation ladder (weak-model support)

Parse attempts, in order. The first that succeeds wins; each step is logged.

1. Fenced `envelope` block, valid JSON.
2. Any fenced block, valid JSON with at least a `say` key.
3. First `{ ... }` substring that parses as JSON with at least a `say` key.
4. Line-oriented fallback: lines starting with `say:`, `ask:`, `next:`; `patch` empty.
5. **Prose-only**: the entire raw output becomes `say`; `ask`, `patch` empty; `next` null.

One **repair pass** is allowed if `settings.repair_pass` is on and steps 1–3 failed, provided the turn deadline permits it. If that also fails, fall to step 5.

Rule: a model that cannot produce a patch still produces a useful nudge. Nothing is ever applied from an unparsed or partially parsed patch. The ladder never *invents* ops.

### 9.4 Model agnosticism

- No provider-specific tool calling, structured output modes or system-role assumptions in the core. Adapters may use them internally; the contract is `string → string`.
- Adapter must be swappable without migration of the store.
- The session engine runs identically with no adapter configured. "No model" is a valid, fully functional configuration.

---

## 10. Modality

Modality adapters sit on the edges and never touch the store.

- **Input**: keyboard → text; STT → text; buttons → session events. A front-end may translate speech into `finish`, `snooze`, `stop`, `commit`; it may not decide them.
- **Output**: screen renders announcements, `say`/`ask`, proposals and the round diff; TTS speaks announcements and `say`/`ask` only (never patches or diffs).
- **Announcements are first-class output**: they must be deliverable even when the screen is off, since reminders during WORK are the system's main voice.
- **Policy, not model, chooses output modality**: `settings.modality_policy`. The model has no verb for this.
- **Hard stop enforcement** is announcement only **[default]**. An input lock at "Stop." is a front-end option; compliance is Man's.

---

## 11. Views

Five views, all renderings of the store. **No view contains logic that changes state except by emitting a patch or a session event through the script.**

| View | Shows | Emits |
|---|---|---|
| **Grid** | Nodes as rows: status, due, progress, links, quick-log. The working surface. | human patches |
| **Graph** | Tree + deps as a mind map. D and N highlighted. Proposals shown as diffs; accept / reject / edit-then-accept per op or whole. Undo/redo. | human patches, proposal dispositions, commit |
| **Session** | Current state, countdown, next reminder, z of Zmax, seated time, round diff; buttons for finish, snooze, stop, commit, end. | session events |
| **Settings** | `SessionConfig`, attention policy, modality policy, adapter selection, limits, retention. | settings changes |
| **Schedule** | Upcoming `ScheduleEntry`s, initiative rules on/off, attention snooze. | schedule changes |

`SessionConfig` changes apply at the next `start_session`, never mid-session.

---

## 12. Logging

Three levels, each append-only, each with its own retention setting.

| Log | Content | Default retention |
|---|---|---|
| **Patch log** | Every applied patch with inverse (§3.3). Part of the store. | forever |
| **Turn log** | Per turn: trigger, projection, prompt, raw output, ladder step, validation result, outcome, latency, deadline met or missed. | 90 days |
| **System log** | Every engine transition with timestamp and cause, every announcement, policy decisions, adapter errors, persistence events, schedule firings. | 30 days |

The turn log answers "why did it say that". The system log answers "why did it *not* say anything" and "why did the round end when it did". Logs are never projected to the model.

---

## 13. Invariants

Script enforces these at all times; a violation is a bug, not a condition.

1. `store.version` equals the number of applied patches since the last snapshot reset.
2. Every node except root has a `parent` that exists.
3. No cycles in `parent` or `deps`.
4. At most one node is `doing`, at most one is `next`, and they are distinct.
5. A node is `blocked` if and only if some dep is not `done`.
6. At most one `PendingQuestion`.
7. Model-authored ops never appear in the patch log without a corresponding human acceptance in the turn log.
8. Nothing is sent to the model that is not in `project(store, trigger)`.
9. The envelope has exactly the four keys after parsing; unknown keys are dropped and logged.
10. Every engine transition is a row in the table in §6.5, and every phase length is the formula in §6.2.
11. No model turn starts in WORK, TIME_UP, SNOOZE or BREAK, and no model output is rendered in those states.
12. The engine's behaviour is identical with and without a model adapter.

---

## 14. Non-goals (v2)

- Implementation language, UI framework, platform, hosting, sync, auth.
- Reading, indexing or summarising the content behind `links`.
- Multiple humans, shared graphs, or one engine serving several workers.
- Free-form chat with history.
- Model-initiated actions outside the four verbs.
- Rich media in nodes.
- Protecting against gaming. Man controls the map and could misreport done as easily as anything else.
- A pause event. Interruptions are `end_session`; the map survives, the sitting clock does not.

---

## 15. Extension points

| Want | Do this | Do not |
|---|---|---|
| New kind of nudge | Add an initiative rule | Add a verb |
| New model | Write an adapter | Change the template contract |
| Voice, watch, widget | Add a modality adapter | Let the model choose modality |
| Richer notes | Put a link in `links` | Add content fields to Node |
| Model remembers something | It patches `ai_note` | Add history |
| New view | Render the store | Let the view write state directly |
| Proof of movement | Add an `activity` sensor | Ask the model to judge it |
| Different pacing | Change `SessionConfig` | Change the formulas |
| Floor on short status phases | Enable the optional `max(q, …)` floor as a setting | Change the formula |

---

## 16. Defaults chosen

Every `[default]` in this document, in one place. Each is a decision the implementation must honour unless a setting says otherwise.

| # | Gap | Default |
|---|---|---|
| 1 | Sitting limit and break length | Ls 45 min, Lb 3 min; to be replaced from current health guidance |
| 2 | Grace window | G = 10 s |
| 3 | No answer at time-up | `stop` after G |
| 4 | Strategy ends with no choice | Auto-commit from N and oldest open node |
| 5 | D vacant mid-round | Promote N; round continues |
| 6 | What counts toward x | Any node cleared in the round and still done, including children and same-round additions |
| 7 | Clears during status / strategy / break | Count toward no round |
| 8 | Crossing out a parent | Cascades to unfinished descendants |
| 9 | Ending STATUS early | Not allowed |
| 10 | Patches during BREAK | Blocked |
| 11 | Proof of movement | Trust Man; optional sensor |
| 12 | Seated time in IDLE | Not counted; long idle resets |
| 13 | Hard stop enforcement | Announcement only |
| 14 | D is blocked | Commit refused |
| 15 | Pending question during session | Expires at end of next STRATEGY |
| 16 | Proposals undispositioned at commit | Expire silently; not recorded as declined |
| 17 | Late model output | `say` discarded, `ask` dropped, `patch` kept for next STRATEGY |
| 18 | `remove_node` | Man only, leaves only, never a node that has held a slot or been done |

---

## 17. Open decisions deferred to implementation

- ULID vs UUID for `id`.
- Snapshot cadence and log compaction.
- Exact values for every `settings` limit not listed in §16.
- Prompt template wording, per adapter family, within the §9.1 constraints.
- Whether a desk-input sensor is shipped by default or left as an extension.
- Whether a `pause` event is needed after real use. If added, it must freeze every timer and the sitting clock, and it is a 2.x minor addition, not a verb.

---

## 18. Change control and migration from 1.0

### 18.1 Breaking changes

| 1.0 | 2.0 | Migration |
|---|---|---|
| status `todo` | `open` | rename |
| status `active` (any number) | `doing` (at most one) | if several, the most recently updated keeps `doing`; others become `open` |
| status `dropped` | `crossed_out` | rename |
| — | status `next` | new; vacant after migration |
| `remove_node` for any leaf | man only, typo repair only | existing log entries stay valid |
| `blocked` set by patch | derived from `deps` | recompute on migration |
| initiative triggers any time | suppressed during sessions | no data change |
| trigger kinds: 4 | 5 (`phase`) | no data change |
| `store.schema_version` 1 | 2 | — |

The patch log is replayed through the migration so undo across the boundary still works.

### 18.2 Frozen for all 2.x versions

- §4 (Sealed Verbs).
- §6.2 (phase-length formulas) and §6.5 (transition table). Defaults in §16 may become settings; formulas and transitions may not change.
- §13 (Invariants).

Node schema may gain optional fields in a minor version; never lose or rename one. Any proposal to add a fifth verb, a sixth engine input, or a model-controlled timer requires a v3 and a written argument for why it cannot be expressed through the existing verbs, the graph, the engine configuration, or an external system.
