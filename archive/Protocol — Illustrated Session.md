# Timeboxed Work Protocol — Illustrated Session

The smallest session that exercises every rule in the protocol: three rounds, one movement break. All timings are hypothetical, and the sitting limit is shrunk far below realistic values so it triggers within the example.

A knows only that B has a goal, that the goal has nodes with labels, and what each node's status is. A never sees or asks about the content of the work.

---

## Setup

### Parameters

| Parameter | Value | Note |
|---|---|---|
| R | 6 min | Round length |
| r | 3 | Reminders per round |
| q | 6 / 2³ = **45 s** | Base unit: snooze, strategy |
| Reminders | 3:00, 1:30, **1:00** left | Third is clamped: max(1 min, 0:45) |
| Zmax | 3 | Snoozes per round |
| Ls | 15 min | Sitting limit (illustrative only) |
| Lb | 2 min | Movement break |

### Status phase lengths used in this session

q · 2^(z+1) / (x + 1)

| Round | z | x | Length |
|---|---|---|---|
| 1 | 0 | 2 | 45 · 2 / 3 = **30 s** |
| 2 | 1 | 1 | 45 · 4 / 2 = **1:30** |
| 3 | 3 | 0 | 45 · 16 / 1 = **12:00** |

### Starting map (as A sees it)

```
GOAL
├─ n1  open
├─ n2  open
├─ n3  open
└─ n4  open
```

---

## Session

Session clock is shown as `[mm:ss]`. Round timers count down separately.

### Round 1 — in the zone

```
[00:00]  B: Doing n1, next n2.
         A: n1 doing, n2 next. 6 minutes, starting now.
```
> **Commit.** The first commit of a session has no strategy phase before it.

```
[02:10]  (B adds n5 to the map, status open)
```
> **Live map.** B edits mid-round. A doesn't need to be told.

```
[03:00]  A: 3 minutes left.
```
> **Reminder 1** (R/2).

```
[04:20]  (B marks n1 done, and n3 done — resolved along the way)
         B: Done.
         A: Round over at 4:20. Status, 30 seconds.
```
> **Early completion.** x = 2, z = 0. In the zone, so the status phase is shorter than q.

```
[04:20]  B: n1 done, n3 done, n5 added.
         A: Got it.
[04:25]  (B stands, stretches)
```
> **Status phase (30 s).** The report takes 5 seconds because the map is already current. The rest is away time.

```
[04:50]  A: Strategy, 45 seconds.
[05:10]  B: Doing n2, next n4. Done.
```
> **Strategy, ended early** by B at 20 s.

```
[05:10]  A: Seated 5:10. Next round brings it to 11:10, under 15. Continue.
```
> **Sitting check.** The 30 s status phase was shorter than Lb, so it didn't reset the clock.

**Map after round 1**
```
├─ n1  done
├─ n2  doing
├─ n3  done
├─ n4  next
└─ n5  open
```

### Round 2 — a dead end and a snooze

```
[05:10]  A: n2 doing, n4 next. 6 minutes, starting now.
[08:10]  A: 3 minutes left.
```

```
[09:00]  (B crosses out n2, marks n4 doing, n5 next)
```
> **D crossed out mid-round.** B switches to a new doing node and keeps the round going. n2 stays visible on the map for history and won't count toward x.

```
[09:40]  A: 1:30 left.
[10:10]  A: 1 minute left.
```
> **Reminders 2 and 3.** Reminder 3 would have been at 0:45 left; the clamp moves it to 1:00 as a get-ready-to-stop signal.

```
[11:10]  A: Time's up.
         B: Snooze.
         A: Snooze 1 of 3. 45 seconds.
```
> **Snooze.** B judges n4 is close: a bet worth taking.

```
[11:40]  (B marks n4 done)
         B: Done.
         A: Status, 1:30.
```
> **Bet paid off.** x = 1, z = 1. Total cost over stopping at 11:10: 30 s of snooze + 1:30 status = 2:00, with n4 cleared. Stopping would have cost 1:30 status with nothing cleared.

```
[11:40]  B: n2 crossed out, n4 done.
         A: Got it.
[11:45]  (B gets water)
[13:10]  A: Strategy, 45 seconds.
         (B adds n6)
[13:55]  B: Doing n5, next n6.
```
> **Status (1:30) and full strategy (45 s).** B uses all of strategy this time.

```
[13:55]  A: Seated 13:55. Next round brings it to 19:55, over 15. Movement break first, at least 2 minutes.
         (B walks)
[15:55]  A: Sitting clock reset.
```
> **Sitting limit.** Triggered at a round boundary, independent of how rounds are going. The 1:30 status phase was under Lb, so it didn't reset the clock.

**Map after round 2**
```
├─ n1  done
├─ n2  crossed out
├─ n3  done
├─ n4  done
├─ n5  doing
└─ n6  next
```

### Round 3 — stuck, pushing through

```
[15:55]  A: n5 doing, n6 next. 6 minutes, starting now.
[18:55]  A: 3 minutes left.
[20:25]  A: 1:30 left.
[20:55]  A: 1 minute left.
[21:55]  A: Time's up.
         B: Snooze.
         A: Snooze 1 of 3.
[22:40]  A: Time's up.
         B: Snooze.
         A: Snooze 2 of 3.
[23:25]  A: Time's up.
         B: Snooze.
         A: Snooze 3 of 3.
[24:10]  A: Time's up.
         B: One more.
         A: No snoozes left. Stop.
```
> **Hard stop.** Zmax = 3 reached; A refuses the fourth.

```
[24:10]  B: n5 still doing. Added n7, n8 under it.
         A: Got it. Status, 12 minutes.
```
> **Slowdown.** x = 0, z = 3, so the status phase is 12:00. Had B stopped at 21:55 instead of snoozing, the status phase would have been 1:30 and strategy would have started at 23:25, not 36:10: about 12:45 saved.

```
[24:15]  (B leaves the desk: walk, water, eyes off the task)
[36:10]  A: Sitting clock reset. Strategy, 45 seconds.
```
> **Long status phase resets the sitting clock**, because it's ≥ Lb and B moved.

```
[36:55]  B: Doing n7, next n8.
         A: Seated 0:45. Next round brings it to 6:45. Continue.
```
> The cycle continues from here.

**Map after round 3**
```
├─ n1  done
├─ n2  crossed out
├─ n3  done
├─ n4  done
├─ n5  open
│  ├─ n7  doing
│  └─ n8  next
└─ n6  open
```

---

## Session Summary

| Round | Start | Work + snooze | z | x | Status | Strategy | Seated after | Note |
|---|---|---|---|---|---|---|---|---|
| 1 | 00:00 | 4:20 | 0 | 2 | 0:30 | 0:20 (early) | 5:10 | In the zone |
| 2 | 05:10 | 6:30 | 1 | 1 | 1:30 | 0:45 | 13:55 → break | D crossed out; snooze paid off |
| — | 13:55 | — | — | — | — | — | 0:00 | Movement break 2:00 |
| 3 | 15:55 | 8:15 | 3 | 0 | 12:00 | 0:45 | 0:45 | Stuck; all snoozes; long reset |

---

## Coverage Checklist

| Rule | Where |
|---|---|
| Commit D and N | Every round |
| Reminders at R/2, R/4 | R1 03:00; R2 08:10, 09:40 |
| 1-minute clamp on reminders | R2 10:10; R3 20:55 |
| Live map edits by B mid-round | R1 02:10, 04:20; R2 09:00 |
| Node crossed out, history kept | R2 09:00 |
| D replaced mid-round | R2 09:00 |
| Crossed-out node not counted in x | R2 status |
| Early completion of work round | R1 04:20; R2 11:40 (during snooze) |
| Early completion of strategy | R1 05:10 |
| Snooze that pays off | R2 11:10 |
| All snoozes used, extra refused | R3 24:10 |
| Status phase: x = 2 (shorter than q) | R1 |
| Status phase: x = 1 (neutral) | R2 |
| Status phase: x = 0 with snoozes (escalation) | R3 |
| Status as report + away time | Every status phase |
| Nodes added during strategy / status | R2 13:10; R3 24:10 |
| Sitting limit triggers movement break | After R2 |
| Short status phase doesn't reset sitting clock | R1, R2 |
| Long status phase resets sitting clock | R3 |
| A never needs node content | Throughout: only labels and statuses |
