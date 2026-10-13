# Machine-Prompts-Man: System Specification

**Version:** 1.0 (sealed)
**Status:** Design spec. Implementation and hosting are out of scope and live in separate documents.

---

## 0. Purpose

A system in which the machine initiates interaction with the human, rather than waiting to be asked. The human keeps a structured plan (a graph of tasks); the machine watches it, nudges, asks, and proposes changes at the right moments; the human accepts, rejects, or ignores.

Design goals, in priority order:

1. **Simple.** Few moving parts, each with one job.
2. **Effective.** The nudges are timely, relevant, and not annoying.
3. **Closed for modification, open for extension.** The core protocol is sealed. New capability comes from outside the core (external notes, new model adapters, new modality adapters), never from widening the protocol.
4. **Model agnostic.** Any LLM, including weak ones that cannot reliably follow output formats, must work with degraded but safe behaviour.
5. **Inspectable.** Every state change and every model exchange is logged.

---

## 1. Principles

- **The graph is the memory.** There is no conversation history. The model's only memory of the past is what has been written into the graph.
- **The human owns the graph.** Model changes are always proposals. Human changes apply immediately.
- **Script does mechanics, model does judgement.** Triggering, validation, persistence, scheduling, and projection are deterministic code. Phrasing, prioritisation, and suggestions are the model's.
- **The model never sees the whole store.** It sees a projection, computed by a pure function.
- **Four verbs, forever.** The model's output vocabulary is `say`, `ask`, `patch`, `next`. See §4 (Sealed Verbs).
- **Notes live outside.** The system stores task structure, not task content. Content is a link to wherever the human keeps it.

---

## 2. Vocabulary

| Term | Meaning |
|---|---|
| **Man** | The human. |
| **Model** | The LLM behind a model adapter. |
| **Store** | Canonical state: nodes + patch log + a small amount of system state. |
| **Node** | One task/step/topic in the graph. |
| **Graph** | The tree of nodes plus dependency edges. |
| **Projection** | The text the model receives, computed from the store. |
| **Patch** | An ordered list of ops that change the store. |
| **Proposal** | A patch authored by the model, awaiting human disposition. |
| **Trigger** | An event that starts a turn. |
| **Turn** | One cycle: trigger → projection → model → envelope → disposition. |
| **Envelope** | The parsed model output: the four verbs. |
| **Modality** | An input or output channel (keyboard, STT, screen, TTS). |
| **View** | A rendering of the store (grid, graph, settings, schedule). |

---

## 3. State

### 3.1 Node schema

```
Node {
  id          : string      // stable, opaque, never reused (ULID recommended)
  title       : string
  parent      : id | null   // null only for the root
  deps        : id[]        // "cannot start until these are done"
  status      : "todo" | "active" | "blocked" | "done" | "dropped"
  due         : date | null
  progress    : 0..100
  description : string      // short; one paragraph max
  links       : url[]       // where the real notes live (Docs, Notion, files)
  ai_note     : string      // model's scratchpad for this node; model may patch
  flags       : string[]    // e.g. "no_suggest", "pinned"
  created_at  : datetime
  updated_at  : datetime    // set by script on every change to this node
}
```

Rules:

- The graph is a **tree** via `parent`, with optional **dependency edges** via `deps`. It is not a free graph. Cycles in `deps` are rejected.
- `links` is the extension point for notes. The system never fetches or parses link targets. This keeps the store small, private, and closed.
- `ai_note` is the only field intended for the model's own memory. Humans may read and clear it.
- `flags` is an open string set, but only flags listed in this spec have system meaning:
  - `no_suggest` — model must not propose changes to this node or nudge about it.
  - `pinned` — always included in full in the projection.

### 3.2 Store

```
Store {
  schema_version : int
  version        : int          // increments on every applied patch
  nodes          : Node[]
  patch_log      : LogEntry[]   // append-only
  pending        : Proposal[]   // model proposals awaiting disposition
  question       : PendingQuestion | null
  declined       : Declined[]   // recent rejections, with TTL
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
  base       : int          // store.version before applying
  ops        : Op[]
  inverse    : Op[]         // computed by script at apply time
  turn_id    : string | null
}
```

Consequences:

- **Undo/redo** = apply `inverse` / reapply `ops`.
- **Persistence** = snapshot of `nodes` + the log. Rebuild is replay.
- **Audit** = the log.
- **Conflict detection** = `base` check (see §5.3).

### 3.4 Small system state

```
Proposal       { id, turn_id, at, ops, say }           // see §5.2
PendingQuestion{ turn_id, at, text, expires_at }       // see §7.4
Declined       { node_id | null, summary, at, expires_at }  // see §7.5
Settings       { quiet_hours, max_nudges_per_day, timezone, modality_policy, ... }
ScheduleEntry  { id, at | cron, reason, source: "man" | "model" }
```

---

## 4. Sealed Verbs

**Directive: the model output vocabulary is exactly these four verbs. No verb may be added, removed, or renamed. Any desired new capability must be expressed through these verbs, through the graph, or outside the system. This section is not subject to revision in v1.x.**

```
Envelope {
  say   : string                  // prose for the human. May be empty.
  ask   : string | null           // a question that expects an answer.
  patch : Op[]                    // proposed graph changes. May be empty.
  next  : datetime | null         // when the model wants to be woken again.
}
```

Semantics:

- **say** — rendered to the human via the output modality. Never changes state.
- **ask** — like `say`, but sets `store.question`. The next human message is routed as an *answer* (§7.4). At most one open question at a time.
- **patch** — becomes a **proposal**, never applied directly. Validated by script before it is even shown (§5.4).
- **next** — creates a `ScheduleEntry` with `source: "model"`, subject to attention policy (§7.3). The model schedules its own follow-up; policy bounds it.

What is deliberately *not* a verb: tool calls, modality selection, search, fetching links, sending messages to third parties, deleting the store. If it feels like it needs a fifth verb, it belongs outside the core.

---

## 5. Patch Protocol

### 5.1 Ops

```
add_node    { tmp_id, parent, title, status?, due?, progress?, description? }
update_node { id, fields: { ...subset of mutable fields... } }
move_node   { id, parent }
remove_node { id }            // only leaves; non-leaves must be dropped, not removed
add_dep     { id, dep }
remove_dep  { id, dep }
```

- `tmp_id` in `add_node` lets a single patch reference nodes it creates. Script assigns real ids on apply.
- Mutable by anyone: `title, parent, deps, status, due, progress, description, links, flags`.
- Mutable by model only via proposal: all of the above plus `ai_note`.
- Never mutable by model: `id, created_at, updated_at, flags` containing `no_suggest` (model cannot remove it).

### 5.2 Author rules

| Author | Applied when |
|---|---|
| man | Immediately, if valid. |
| model | Only when the human accepts the proposal (whole or per-op). |
| system | Immediately (e.g. `updated_at`, status auto-transitions if configured). |

A proposal is presented with its `say` text so the human sees the reasoning next to the change.

### 5.3 Base version and conflicts

Every patch carries `base`. On apply, if `base != store.version`:

- Author `man`: rebase if ops touch only nodes unchanged since `base`; otherwise reject and re-render.
- Author `model`: the proposal is marked **stale** and shown as such. Human may still accept op-by-op; stale ops that touch changed nodes are blocked.

### 5.4 Validation (script, before anything is shown)

Reject the whole patch, with a logged reason, if any op:

- references an unknown id or an invalid parent;
- creates a `deps` cycle or a `parent` cycle;
- removes a non-leaf;
- touches a node flagged `no_suggest` (model author only);
- sets a field outside the mutable set for that author;
- exceeds limits: more than **N ops per patch** (default 12) or more than **M new nodes** (default 5).

Reject only the offending ops instead if `settings.lenient_validation` is on. Default is whole-patch rejection: predictable beats clever.

---

## 6. Projection

`project(store, trigger) → string` is a **pure function**. It is the only thing the model sees, together with the fixed prompt template.

### 6.1 Contents, in order

1. Current datetime and timezone.
2. Trigger: kind and reason (§7.1), plus the human message if any.
3. If a question is pending: the question text, marked as such.
4. Recently declined suggestions (§7.5), as one line each.
5. The graph, rendered per §6.2.

### 6.2 Rendering rules

- `pinned`, `active`, `blocked`, and overdue nodes: full fields except `links`.
- `todo` nodes: title, due, progress, one-line description.
- `done`/`dropped` subtrees: collapsed to `[done] <title> (n children)`.
- `no_suggest` nodes: title only, marked `[locked]`.
- `description` truncated to a configurable length.
- `ai_note` included in full for any node rendered in full.
- Per-node freshness: `updated <n> days ago`. Never the raw log.
- Hard cap on total size; if exceeded, drop `todo` nodes furthest from the trigger's focus nodes first, then collapse deeper levels.

### 6.3 Format

Indented plain text with stable node ids visible, e.g.

```
[n_01HX...] Launch v2  (active, due 2026-11-01, 40%)
  [n_01HY...] Write spec  (done)
  [n_01HZ...] Build API  (active, due 2026-10-20, 60%, updated 3d ago)
    note: user prefers to batch backend work on Fridays
  [n_01J0...] Design review  (blocked by n_01HZ)
```

Not JSON. Plain text projects better across models and is cheaper.

---

## 7. Turn Engine

### 7.1 Triggers

All turns start with exactly one trigger:

| Kind | Source | Reason field |
|---|---|---|
| `message` | human typed/spoke | free text |
| `answer` | human replied while `question` pending | free text |
| `schedule` | `ScheduleEntry` fired | `source` + `reason` |
| `initiative` | initiative rule fired (§7.2) | rule name + node ids |

Triggers are serialised: one turn at a time. Triggers arriving during a turn queue; duplicate initiative triggers collapse.

### 7.2 Initiative rules (script, not model)

Deterministic rules decide *that* a nudge is warranted and *why*; the model decides *how to say it*. Initial rule set:

- `overdue` — `due < today` and status not done/dropped.
- `due_soon` — `due` within `settings.due_soon_days`.
- `stale` — `active` and `updated_at` older than `settings.stale_days`.
- `unblocked` — a `blocked` node whose deps are all now done.
- `drift` — `progress` unchanged for `settings.drift_days` on an `active` node.

Rules are configurable and may be added without touching the protocol.

### 7.3 Attention policy (script)

Applied to every `schedule` and `initiative` trigger before it is allowed to wake the model:

- **Quiet hours**: suppressed, deferred to end of window.
- **Daily budget**: `max_nudges_per_day`; excess deferred to next day, highest-priority rule first.
- **Snooze**: human can snooze a node or the whole system for a duration.
- **Model `next`**: clamped to `[min_interval, max_interval]`; cannot bypass quiet hours or budget.
- **Coalescing**: multiple pending initiative triggers merge into one turn with multiple reasons.

### 7.4 Pending question

- `ask` sets `store.question` with an `expires_at` (default: next quiet-hours boundary).
- A human message while a question is pending is routed as an `answer` trigger, which includes the question text in the projection.
- Answer or expiry clears the slot. There is never more than one. This is the whole of multi-turn memory, by design.

### 7.5 Declined memory

- When a proposal is rejected, script writes a `Declined` entry: the node ids touched and a one-line summary (derived from the ops, not from the model), with a TTL (default 14 days).
- The projection includes active entries so the model does not repeat itself.
- Human can promote a decline to a permanent `no_suggest` flag on the node.

### 7.6 Turn lifecycle

```
1. trigger accepted (policy passed)
2. turn_id assigned; turn log opened
3. projection = project(store, trigger)
4. prompt = template + projection
5. raw = adapter.complete(prompt)
6. envelope = parse(raw)            // §8
7. validate(envelope.patch)         // §5.4
8. side effects:
     say   → render via modality policy
     ask   → set question
     patch → store.pending += proposal
     next  → schedule (policy-clamped)
9. turn log closed with outcome
```

A turn that fails at any step logs the failure and does nothing to the store. The human is told something went wrong only if the trigger was a `message` or `answer`.

---

## 8. Model Adapter

The single model-specific component. Interface:

```
complete(prompt: string) → raw: string
```

Everything else below is shared script.

### 8.1 Prompt template

Fixed per spec version. Contains: role, the four verbs with one worked example, the projection, and the output format instruction. Must be short. No chain-of-thought instructions; weak models do worse with them.

### 8.2 Output format

Preferred: a single fenced block containing JSON with the four keys. Prose outside the block is ignored. Example in the template:

```
```envelope
{"say":"...","ask":null,"patch":[],"next":"2026-10-14T09:00"}
```
```

### 8.3 Degradation ladder (weak-model support)

Parse attempts, in order. The first that succeeds wins; each step is logged.

1. Fenced `envelope` block, valid JSON.
2. Any fenced block, valid JSON with at least a `say` key.
3. First `{ ... }` substring that parses as JSON with at least a `say` key.
4. Line-oriented fallback: lines starting with `say:`, `ask:`, `next:`; `patch` empty.
5. **Prose-only**: the entire raw output becomes `say`; `ask`, `patch` empty; `next` null.

Then: one **repair pass** is allowed if `settings.repair_pass` is on and step 1–3 failed: re-prompt with "Return only the envelope block" and the raw output. If that also fails, fall to step 5.

Rule: a model that cannot produce a patch still produces a useful nudge. Nothing is ever applied from an unparsed or partially parsed patch. The degradation ladder never *invents* ops.

### 8.4 Model agnosticism

- No provider-specific tool calling, structured output modes, or system-role assumptions in the core. Adapters may use them internally to produce `raw`, but the contract is `string → string`.
- Adapter must be swappable without migration of the store.

---

## 9. Modality

Modality adapters sit on the edges and never touch the store.

- **Input**: keyboard → text; STT → text. Both produce a `message` or `answer` trigger. Identical downstream.
- **Output**: screen renders `say`/`ask` and proposals; TTS speaks `say`/`ask` only (never patches).
- **Policy, not model, chooses output modality**: `settings.modality_policy` (e.g. `screen`, `voice`, `auto` by device state). The model has no verb for this and should not be asked.
- **Text-to-visualisation** is a view concern (§10): the graph view is the visualisation of the store.

---

## 10. Views

Four views, all renderings of the store. **No view contains logic that changes state except by emitting a patch through the script.**

| View | Shows | Emits |
|---|---|---|
| **Grid** | Nodes as rows: status, due, progress, links, quick-log. The human's working surface. | human patches |
| **Graph** | Tree + deps as a mind map. Proposals shown as diffs; accept / reject / edit-then-accept per op or whole. Undo/redo. | human patches, proposal dispositions |
| **Settings** | Attention policy, modality policy, model adapter selection, limits, log retention. | settings changes |
| **Schedule** | Upcoming `ScheduleEntry`s (both sources), initiative rules on/off, snooze. | schedule changes |

The grid's "notes" are `links`. The grid may grow conveniences over time (quick-log, link previews) but these are view-level and do not change the store schema.

---

## 11. Logging

Three levels, each append-only, each with its own retention setting.

| Log | Content | Default retention |
|---|---|---|
| **Patch log** | Every applied patch with inverse (§3.3). Part of the store. | forever |
| **Turn log** | Per turn: trigger, projection text, prompt, raw model output, parse ladder step reached, validation result, outcome, latency. | 90 days |
| **System log** | Policy decisions (suppressed/deferred/coalesced triggers), adapter errors, persistence events, schedule firings. | 30 days |

The turn log is the debugging surface for "why did it say that": the exact projection is there. The system log is the debugging surface for "why did it *not* say anything."

Logs are never projected to the model.

---

## 12. Invariants

Script enforces these at all times; a violation is a bug, not a condition.

1. `store.version` equals the number of applied patches since the last snapshot reset.
2. Every node except root has a `parent` that exists.
3. No cycles in `parent` or `deps`.
4. At most one `PendingQuestion`.
5. Model-authored ops never appear in the patch log without a corresponding human acceptance in the turn log.
6. Nothing is sent to the model that is not in `project(store, trigger)`.
7. The envelope has exactly the four keys after parsing; unknown keys are dropped and logged.

---

## 13. Non-goals (v1)

- Implementation language, UI framework, platform, hosting, sync, auth. Separate document.
- Reading, indexing, or summarising the content behind `links`.
- Multiple humans or shared graphs.
- Free-form chat with history.
- Model-initiated actions outside the four verbs (sending email, editing external docs, web search).
- Rich media in nodes.

---

## 14. Extension points (how to grow without reopening the core)

| Want | Do this | Do not |
|---|---|---|
| New kind of nudge | Add an initiative rule | Add a verb |
| New model | Write an adapter | Change the template contract |
| Voice, watch, widget | Add a modality adapter | Let the model choose modality |
| Richer notes | Put a link in `links` | Add content fields to Node |
| Model remembers something | It patches `ai_note` | Add history |
| New view | Render the store | Let the view write state directly |

---

## 15. Open decisions deferred to implementation

- ULID vs UUID for `id`.
- Snapshot cadence and log compaction.
- Exact default values for every `settings` limit.
- Whether `system` author may auto-transition `blocked → todo` on `unblocked`, or only raise the initiative trigger.
- Prompt template wording, per adapter family, within the §8.1 constraints.

---

## 16. Change control

- §4 (Sealed Verbs) and §12 (Invariants) are frozen for all 1.x versions.
- Node schema may gain optional fields in a minor version; never lose or rename one.
- Any proposal to add a fifth verb requires a v2 and a written argument for why it cannot be expressed through the existing verbs, the graph, or an external system.
