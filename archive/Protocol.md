# Timeboxed Work Protocol

A protocol in which a Timekeeper (A) manages time for a Worker (B) who is pursuing a goal through a mind map of work nodes. The protocol is built from a single base time unit, and its timing rules are designed so that the system self-regulates: clean rounds keep context switching to a minimum, while rounds that go badly automatically produce longer pauses away from the task.

---

## 1. Roles

**B — the Worker.** Has a goal and partial knowledge of how to reach it. Does the work, makes all decisions about what to work on, and keeps the mind map current.

**A — the Timekeeper.** Keeps time, gives alerts, receives B's status reports, and enforces the timing rules (reminders, snooze limits, phase lengths, sitting limit).

---

## 2. Scope

The protocol assumes B reports honestly. B controls the map, so B could misreport what is done just as easily as misreport status. Protecting against gaming is out of scope.

---

## 3. The Mind Map

The plan is a mind map of nodes. Each node is a piece of work toward the goal.

### 3.1 Node statuses

| Status | Meaning |
|---|---|
| open | Known work, not currently planned |
| doing | The node B is working on now (**D**) |
| next | The node B expects to work on after D (**N**) |
| done | Cleared |
| crossed out | Abandoned or no longer relevant; kept on the map for history |

### 3.2 Rules

- B may change the map at any time, including mid-round: add nodes, change statuses, cross nodes out.
- Nodes are crossed out, never deleted, so the history of the plan is preserved.
- At any moment exactly one node is *doing* and one is *next*.
- D may be crossed out mid-round. B then either sets a new *doing* node and continues the round, or declares done to end the round early.
- Crossed-out nodes do not count as cleared.
- The map is expected to be in constant flux.

---

## 4. Parameters

### 4.1 Inputs

| Symbol | Meaning | Example |
|---|---|---|
| **R** | Length of a work round | 5 min |
| **r** | Number of reminders A gives within R (before the time-up alert) | 3 |
| **Ls** | Sitting limit: max continuous seated work time | e.g. 60 min |
| **Lb** | Movement break: minimum time away to reset the sitting clock | e.g. 2 min |

Constraint: **r ≥ 1**.

Ls and Lb should be set from current guidance on sedentary time from a health organization or professional.

### 4.2 Base unit

**q = R / 2^r**

Equivalently, **2^r · q = R**.

### 4.3 Derived values

| Item | Length / value |
|---|---|
| Reminder k (k = 1 … r), time remaining | max(1 min, R / 2^k) |
| Strategy phase | q |
| One snooze | q |
| Max snoozes per round (Zmax) | r |
| Status phase | q · 2^(z+1) / (x + 1) |

Reminders that land on the same time after the 1-minute clamp are merged into one, so the final reminder of a round is always at least 1 minute before time-up: a signal to get ready to stop.

### 4.4 Per-round variables

| Symbol | Meaning |
|---|---|
| **z** | Snoozes used in the current round (0 ≤ z ≤ r). Resets every round. |
| **x** | Nodes cleared in the current round. Normally 1. Resets every round. |

---

## 5. The Cycle

### Step 1 — Commit
B tells A the node to work on now (D) and the node B expects to work on next (N). Both are marked *doing* and *next* on the map.

### Step 2 — Work round (length R)
A starts the timer and B works on D. B keeps the map current as work happens.

A gives reminders at max(1 min, R/2), max(1 min, R/4), … max(1 min, R/2^r) remaining, merging any that coincide. When the timer reaches 0, A announces that time is up.

### Step 3 — Snooze (optional)
At time-up, B may snooze, adding q to the round. When the snooze ends, A announces time-up again and B may snooze again, up to r times in total (z ≤ r).

When B declines to snooze, or no snoozes remain, A announces the hard stop. B must stop.

### Step 4 — Status phase (length q · 2^(z+1) / (x + 1))
B reports the status to A. Because B has kept the map current during the round, this is a report, not a fill-in: it is close to instant.

The rest of the phase is time away from the task: stand up, get water, eyes off the screen. In a tight loop (x = 1, z = 0) the phase is short and barely interrupts flow. In a slowdown it grows, giving real distance from the task.

### Step 5 — Strategy (length q)
B reviews the map and chooses the new D and N. N often becomes the new D, but this is not required.

### Step 6 — Sitting check
A compares continuous seated time against Ls (see Section 7). If the next round would exceed it, a movement break is taken first.

### Step 7 — Repeat
Return to Step 1. z and x reset to 0.

---

## 6. Early Completion

B may declare "done" in any phase before its time runs out. This ends the phase immediately and moves to the next one.

Declaring D done early in the work round means x = 1 and z = 0, which gives the shortest status phase of a normal round (q).

---

## 7. Sitting Limit (Systemic Lever)

A health-based limit that applies regardless of how rounds are going. It is independent of x and z.

- A tracks continuous seated work time across rounds.
- Any status phase of length ≥ Lb in which B actually moves resets the clock.
- At the sitting check (Step 6), if the clock plus the next round (R) would exceed Ls, B takes a movement break of at least Lb before committing to the next round. This resets the clock.
- The limit is only enforced at round boundaries, never mid-round, to avoid breaking flow.

This complements the self-correcting dynamics of Section 8.3: those react to signs of fatigue after the fact, while the sitting limit acts preventively, even during a run of clean rounds.

---

## 8. Design Rationale

### 8.1 The status phase is a cost, not a reward
B does not treat breaks as a reward: less context switching is better. The status phase is the price of a round that did not go cleanly, and its length steers B's behavior.

- **x = 1** (one node cleared, the normal case) is neutral: status phase = q · 2^z.
- **x = 0** (nothing cleared) doubles the status phase. B should notice this and stop to rethink rather than snooze.
- **x ≥ 2** shortens the status phase: B is in the zone, and the system interrupts as little as possible. Since reporting is near instant, a status phase shorter than q is fine.

### 8.2 A snooze is a bet
At time-up with D unfinished, B's options cost:

| Choice | Outcome | Extra time before next strategy |
|---|---|---|
| Stop now | x = 0, z = 0 | 2q |
| Snooze, then finish | x = 1, z = 1 | q + 2q = 3q |
| Snooze, still unfinished | x = 0, z = 1 | q + 4q = 5q |
| Two snoozes, still unfinished | x = 0, z = 2 | 2q + 8q = 10q |

Snoozing only pays off when B is genuinely close to clearing the node. When there is no result, stopping and stepping away is cheaper than bashing through.

### 8.3 Self-correcting dynamics (burnout)
In the zone, B runs rounds of x = 1, z = 0, so each cycle is R + 2q with minimal interruption.

Sustained high output can lead to burnout. The protocol relies on its own dynamics to catch this: as fatigue sets in, x starts to fall and z starts to rise, and both lengthen the status phase. The first response is gentle (a missed node doubles the pause to 2q); pushing through with snoozes escalates it steeply, up to 2R.

This correction is deliberately lagging: fatigue must cost at least one round before the system reacts. The sitting limit (Section 7) covers the physical side independently.

---

## 9. Worked Examples

### 9.1 R = 10 min, r = 3

**Base unit:** q = 10 / 2^3 = 1.25 min
**Reminders at:** 5, 2.5, 1.25 min remaining (no clamping needed)
**Strategy:** 1.25 min
**Snooze:** 1.25 min each, up to 3 per round

Status phase length (minutes):

| | x = 0 | x = 1 | x = 2 | x = 3 |
|---|---|---|---|---|
| **z = 0** | 2.5 | 1.25 | 0.83 | 0.63 |
| **z = 1** | 5 | 2.5 | 1.67 | 1.25 |
| **z = 2** | 10 | 5 | 3.33 | 2.5 |
| **z = 3** | 20 | 10 | 6.67 | 5 |

### 9.2 Reminder clamping

| R | r | q | Raw reminders (min remaining) | After max(1 min, …) |
|---|---|---|---|---|
| 10 | 3 | 1.25 | 5, 2.5, 1.25 | 5, 2.5, 1.25 |
| 10 | 4 | 0.625 | 5, 2.5, 1.25, 0.625 | 5, 2.5, 1.25, 1 |
| 5 | 3 | 0.625 | 2.5, 1.25, 0.625 | 2.5, 1.25, 1 |
| 4 | 4 | 0.25 | 2, 1, 0.5, 0.25 | 2, 1 (three merged) |

Clamping only affects reminders. q, and with it snooze, strategy and status lengths, is unchanged.

### 9.3 Sample round: one snooze, then D cleared (R = 10, r = 3)

| Time | Event |
|---|---|
| 0:00 | Round starts, B works on D |
| 5:00 | A: "5 min left" |
| 7:30 | A: "2.5 min left" |
| 8:45 | A: "1.25 min left" |
| 10:00 | A: "Time's up." B snoozes (z = 1) |
| 11:15 | A: "Time's up." B declares D done (x = 1) |
| 11:15–13:45 | Status phase, 2.5 min: B reports (seconds), then steps away |
| 13:45–15:00 | Strategy: new D and N chosen |
| 15:00 | Sitting check, then next round |

### 9.4 Sample clean round: D done early

| Time | Event |
|---|---|
| 0:00 | Round starts |
| 5:00 | A: "5 min left" |
| 6:40 | B declares D done (x = 1, z = 0) |
| 6:40–7:55 | Status phase, 1.25 min |
| 7:55–9:10 | Strategy |
| 9:10 | Sitting check, then next round |

### 9.5 Sitting limit in a run of clean rounds (Ls = 45, Lb = 3)

Each clean cycle is R + 2q = 12.5 min, and its 1.25-minute status phase is shorter than Lb, so the sitting clock keeps running.

| Cycle | Seated time at sitting check | Next round would reach | Action |
|---|---|---|---|
| 1 | 12.5 | 22.5 | Continue |
| 2 | 25 | 35 | Continue |
| 3 | 37.5 | 47.5 | Exceeds 45: movement break ≥ 3 min, clock resets |
| 4 | 12.5 | 22.5 | Continue |

---

## 10. Optional Extensions

Not part of the core protocol; add only if practice shows a need.

- **Status phase floor.** Status phase = max(q, q · 2^(z+1) / (x + 1)), if very short status phases turn out to feel rushed.

---

## 11. Quick Reference

```
q          = R / 2^r
reminders  = max(1 min, R/2^k)  remaining, k = 1..r  (merge duplicates)
snooze     = q        (max r per round)
status     = q · 2^(z+1) / (x + 1)   report is instant, rest is away time
strategy   = q
sitting    = if seated + R > Ls  →  movement break ≥ Lb before next round

cycle      = Commit → Work (R) → [Snooze × z] → Status → Strategy → Sitting check → repeat
z, x reset every round
B updates the map any time; nodes are crossed out, never deleted
"done" ends any phase early
```
