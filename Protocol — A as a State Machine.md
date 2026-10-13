# Timeboxed Work Protocol — A as a State Machine

This document specifies A (the Timekeeper) as a deterministic script. Every decision A makes is a function of the clock, the configuration, the per-round counters, the sitting clock, and the map. A never interprets the content of the work.

Where the protocol spec left a gap, a default is chosen here and marked **[default]**. Section 9 lists every default in one place.

---

## 1. Interface Boundary

A has no authority over anything outside the protocol. It receives events and emits announcements.

**From B (events):** `commit(D, N)`, `done`, `snooze`, `decline`, `edit(op)`, `end_session`
**From the system:** `tick` (timer expiry), and optionally `activity(active | idle)` from a sensor
**To B (announcements):** reminders, time-up, phase starts, refusals, map notices

How events are produced (buttons, commands, or a language model translating speech) is outside this spec. A front-end may translate; it may not decide.

---

## 2. Configuration

| Name | Meaning | Constraint |
|---|---|---|
| R | Round length | R > 1 min |
| r | Reminders per round | r ≥ 1 |
| Ls | Sitting limit | Ls > R |
| Lb | Movement break | Lb > 0 |
| G | Grace window to answer time-up **[default 10 s]** | G > 0 |

`Ls > R` is required, otherwise the sitting check would trigger a break before every round forever.

### 2.1 Derived at session start

```
q          = R / 2^r
Zmax       = r
reminders  = sorted, de-duplicated set of max(60 s, R / 2^k) for k = 1..r
             (each value = time remaining when the reminder fires)
```

---

## 3. State

### 3.1 Session

| Field | Meaning |
|---|---|
| state | Current state (Section 4) |
| seated | Continuous seated time |
| log | Append-only list of every event and map change, timestamped |

### 3.2 Round (reset when WORK is entered)

| Field | Meaning |
|---|---|
| round_start | Timestamp WORK was entered |
| z | Snoozes used |
| x | Nodes cleared, frozen at STATUS entry |

### 3.3 Map

Nodes have `id`, `label`, optional `parent`, and `status ∈ {open, doing, next, done, crossed_out}`.

Invariants:

- At most one node is `doing` and at most one is `next`.
- `doing` and `next` are never the same node.
- Nodes are never deleted.

A slot (doing or next) may be **vacant** temporarily. Section 6 says how vacancies are filled.

---

## 4. States

| State | Meaning | Duration |
|---|---|---|
| IDLE | Session open, waiting for the first commit | Unbounded |
| WORK | Round in progress | R |
| TIME_UP | Round time expired, waiting for snooze decision | G |
| SNOOZE | Extension | q |
| STATUS | Report plus away time | q · 2^(z+1) / (x + 1) |
| STRATEGY | B chooses next D and N | q |
| SIT_CHECK | Instant decision | 0 |
| BREAK | Movement break | Lb |
| END | Session closed | — |

---

## 5. Transitions

### 5.1 Table

| From | Event | Guard | To | Actions |
|---|---|---|---|---|
| IDLE | commit(D, N) | D, N valid | WORK | set slots; start round |
| WORK | tick (reminder) | — | WORK | announce time remaining |
| WORK | done | — | STATUS | freeze x; compute status length |
| WORK | tick (R elapsed) | — | TIME_UP | announce "time's up" |
| TIME_UP | snooze | z < Zmax | SNOOZE | z += 1; announce "snooze z of Zmax" |
| TIME_UP | snooze | z = Zmax | STATUS | announce "no snoozes left, stop"; freeze x |
| TIME_UP | decline | — | STATUS | announce "stop"; freeze x |
| TIME_UP | tick (G elapsed) | — | STATUS | treated as decline **[default]** |
| SNOOZE | done | — | STATUS | freeze x |
| SNOOZE | tick (q elapsed) | — | TIME_UP | announce "time's up" |
| STATUS | tick (length elapsed) | — | STRATEGY | apply sitting reset rule (5.3); show map diff |
| STRATEGY | commit(D, N) | D, N valid | SIT_CHECK | set slots |
| STRATEGY | tick (q elapsed) | — | SIT_CHECK | auto-commit (6.2) |
| SIT_CHECK | — | seated + R > Ls | BREAK | announce break |
| SIT_CHECK | — | otherwise | WORK | start round |
| BREAK | tick (Lb elapsed) | — | WORK | seated = 0; start round |
| any | edit(op) | allowed in state (7.2) | same | apply; log; check vacancies |
| any | end_session | — | END | log |

"Start round" means: `round_start = now`, `z = 0`, schedule reminders and the R timer.

### 5.2 Notes on the table

- `commit` in STRATEGY is how strategy ends early. There is no separate `done` for strategy.
- **STATUS cannot be ended early [default].** It is the cost of the round and the away time. This narrows spec Section 6 ("done ends any phase early"), which predates the status phase becoming away time.
- **BREAK cannot be ended early.** It is a health limit.
- A late `snooze` after the grace window is ignored with the announcement "too late, stop".

### 5.3 Sitting clock

```
seated accumulates in: WORK, TIME_UP, SNOOZE, STATUS, STRATEGY
seated does not accumulate in: IDLE, BREAK, END

at STATUS end:   if status length ≥ Lb and not reported_inactive → seated = 0
at BREAK end:    seated = 0
in IDLE:         if idle duration ≥ Lb → seated = 0
```

Without a sensor, A trusts that B moved **[default]**. With a sensor, `reported_inactive` is true if no movement was detected; a desk-input sensor can serve as a proxy (no keyboard or mouse input for the whole phase).

---

## 6. Map Rules

### 6.1 Computing x

At STATUS entry:

```
x = number of distinct nodes that
      (a) changed to done at some point in [round_start, now), and
      (b) are still done now
```

This includes **[default]**:
- child nodes (any depth)
- nodes added and cleared within the same round
- nodes cleared during SNOOZE

It excludes crossed-out nodes and nodes marked done then reopened. Done-changes made during STATUS or STRATEGY count toward no round.

### 6.2 Vacancy rules [default]

| Situation | What A does |
|---|---|
| D becomes vacant during WORK or SNOOZE (marked done or crossed out) and no new doing is set | Promote N to doing; announce "now doing n". The round continues. |
| D becomes vacant and N is also vacant | Round continues with no doing node; announce "no doing node". B may set one or declare done. |
| N becomes vacant during WORK, SNOOZE or STATUS | Leave vacant until STRATEGY. |
| STRATEGY ends without commit | Auto-commit: D = current N if set, otherwise oldest open node; N = oldest open node not equal to D. Announce the result. |
| Auto-commit finds no open nodes | Go to IDLE; announce "no open nodes". |

"Oldest" means earliest creation in the log. A uses order, never content.

Note that marking D done does not end the round: B keeps working on the promoted N, which is how x ≥ 2 happens. B ends the round with `done`.

### 6.3 Edit operations

| Op | Effect |
|---|---|
| add(label, parent?) | New node, status open |
| set(node, open \| doing \| next \| done) | Setting doing or next moves any previous holder of that slot to open |
| cross_out(node) | Node and its descendants that are open, doing or next become crossed_out **[default]**. Done descendants stay done. |
| restore(node) | crossed_out → open |
| relabel(node, label) | Label change; logged |

### 6.4 Validity of commit(D, N)

D and N must exist, be distinct, and have status open, doing or next. Otherwise A refuses with the reason and stays in the current state.

---

## 7. Permissions by State

### 7.1 Events accepted

| State | commit | done | snooze | decline | edit | end_session |
|---|---|---|---|---|---|---|
| IDLE | ✓ | | | | ✓ | ✓ |
| WORK | | ✓ | | | ✓ | ✓ |
| TIME_UP | | | ✓ | ✓ | ✓ | ✓ |
| SNOOZE | | ✓ | | | ✓ | ✓ |
| STATUS | | | | | ✓ | ✓ |
| STRATEGY | ✓ | | | | ✓ | ✓ |
| BREAK | | | | | | ✓ |

Any other event is ignored with the announcement "not available now".

### 7.2 Edits

Edits are blocked during BREAK **[default]**, so the break stays away from the task. They are allowed everywhere else, including STATUS, where they are the report.

---

## 8. Announcements

| Trigger | Message |
|---|---|
| Round start | "n doing, m next. R starting now." |
| Reminder | "T left." |
| R or snooze elapsed | "Time's up." |
| Snooze accepted | "Snooze z of Zmax." |
| Snooze refused | "No snoozes left. Stop." |
| Decline or grace timeout | "Stop." |
| STATUS start | "Status, L." followed by the map diff for the round |
| STRATEGY start | "Strategy, q." |
| Auto-commit | "No choice made. n doing, m next." |
| Vacancy promotion | "Now doing n." |
| SIT_CHECK → BREAK | "Seated S. Movement break, Lb." |
| BREAK end | "Sitting clock reset." |
| Invalid event | "Not available now." / reason |

---

## 9. Defaults Chosen

| # | Gap in the protocol | Default |
|---|---|---|
| 1 | No answer at time-up | Decline after grace window G (10 s) |
| 2 | Strategy ends with no choice | Auto-commit from N and oldest open node |
| 3 | D vacant mid-round | Promote N; round continues |
| 4 | What counts toward x | Any node cleared in the round and still done, including children and same-round additions |
| 5 | Clears during status/strategy | Count toward no round |
| 6 | Crossing out a parent | Cascades to unfinished descendants |
| 7 | Ending STATUS early | Not allowed |
| 8 | Edits during BREAK | Blocked |
| 9 | Proof of movement | Trust B; optional sensor |
| 10 | Seated time in IDLE | Not counted; long idle resets |
| 11 | Hard stop enforcement | Announcement only; optional input lock is a front-end choice |

---

## 10. Not Covered

- **Interruptions** (a phone call, a visitor). There is no pause event. B can `end_session` and later commit again, which starts a new session with the map intact.
- **Gaming.** Out of scope, as in the protocol spec.
- **Multiple Bs.** One A serves one B.
