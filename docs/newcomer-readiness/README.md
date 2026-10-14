# Newcomer readiness

**The question these documents answer:** a person who has never seen Machine Prompts Man is handed
a Mac with the app installed, Ollama running and a local model ready. What stands between them and
using it well, alone, and what exactly must be built so nothing does?

The documents are written to be followed by a model or a person, in order, without asking
questions. Every claim about today's app cites the file and symbol it comes from. Every change
traces back to a friction entry, and every friction entry forward to a change and a task.

## The documents

| # | Document | What it is | Use it to |
|---|---|---|---|
| 01 | [Operating guide](01-operating-guide.md) | The whole app as it works today, as one walkthrough, with ⚠ markers at each rough edge | Learn the system; keep current as tasks land |
| 02 | [Friction inventory](02-friction-inventory.md) | 50 numbered points where today's app resists a newcomer (F-01…F-50), with cause and severity | Know what is wrong and why |
| 03 | [Required changes](03-required-changes.md) | 30 changes (C-01…C-30), each with what, where, constraints and "done when", plus an F→C traceability table | Know what to build and why it is right |
| 04 | [Task plan](04-task-plan.md) | Tasks 12–27 in four milestones, in the house `tasks/` format, with tests to write first and acceptance lists | Build it, one PR per task |
| 05 | [Design improvements](05-design-improvements.md) | The visual and interaction bar for a client-facing, best-in-class app, in 22 numbered sections, with proposed DESIGN.md amendments | Make it exceptional, not just usable |
| 06 | [Verification protocol](06-verification-protocol.md) | The newcomer test: machine setup, 16 timed steps with pass criteria, the model run, failure drills, results table | Prove it works |

## Reading order

- **To understand the app:** 01.
- **To decide what to fund:** 02's summary table, then 03's headings, then the "Decisions the author
  must make" below.
- **To build:** `CLAUDE.md`, then 04 from the top. Each task tells you which parts of 03, 05,
  `SPEC.md` and `DESIGN.md` to read.
- **To accept the work:** 06.

## How the pieces connect

```
F-nn (02: what resists)  ──closed by──►  C-nn (03: what changes)  ──built in──►  Task NN (04)  ──proved by──►  06 step
                                                    ▲
                                    the bar for how it looks: 05 §n
```

- 02 ends with a summary table; 03 ends with the F→C table; 04 opens with a table of each task's C-
  and F-numbers. Every one of the 50 F-numbers appears in all three.
- When a task merges, mark its F-entries "Closed by task NN (PR #…)" in 02 and update 01's
  walkthrough where behaviour changed. Task 26 checks that nothing is left open.

## Baseline

The documents describe `main` **plus PR #4** (UI polish and host fixes:
https://github.com/ainigh/MAN-MACHINE/pull/4). Items that exist only after PR #4 are marked in 01
and 02. Task 12 depends on PR #4 being merged.

## Constraints that bind every task

From `CLAUDE.md`, restated so no task forgets them:

1. The core is frozen (`Config.swift` formulas, the `Engine.swift` transition table, the envelope's
   four keys, SPEC §13 invariants, the existing core tests). None of the changes needs it to move.
2. Announcements are engine strings; the UI explains beside them and never rewords them.
3. The model is never called in WORK, TIME_UP, SNOOZE or BREAK. The one new request (the Ollama
   warm-up, C-16) is limited to IDLE and no session, and is tested for it.
4. A model that never answers must leave a working app; 06 §5 drills it.
5. The human owns the graph: model patches stay proposals.
6. No cheese: quiet, exact, plain. 05 §17 and §20 say what that means for copy and visuals.
7. Logic in `Host/` with tests that run on Linux; views only lay it out. Strings in `UI/Strings.swift`,
   tokens in `UI/Theme.swift`.

## Decisions the author must make

These changes depart from something an existing task, SPEC section or DESIGN section asked for.
Each has a recommendation; the task that builds it may proceed on the recommendation but must not
merge until the author confirms.

| # | Decision | Today (source) | Recommendation | Change / task |
|---|---|---|---|---|
| D-1 | Refusals: engine text or plain explanation? | "the engine's reason, verbatim" (tasks/05) | Plain explanation for the person; engine text kept verbatim in the monitor | C-13 / 17 |
| D-2 | Do quiet hours silence a session the person started? | yes (tasks/10) | No by default, with a setting; always show "Sounds quiet until …" | C-21 / 20 |
| D-3 | When to ask for notification permission | at the first reminder (tasks/11) | at the first Start session | C-23 / 20 |
| D-4 | Who sees the Monitor | everyone, third segment (DESIGN §12) | developer mode only; a person-facing badge for real problems | C-18, C-19 / 18 |
| D-5 | Self-dismissing surfaces | only those listed in DESIGN §7 | add the one-time close note and toasts | C-02 / 12 (A-4) |
| D-6 | Menu-bar glyph with no session | a square (DESIGN §4) | an outline ring; square only after Stop | 05 §2 / 22 (A-1) |
| D-7 | New tokens and one new motion | DESIGN §3, §5 | `ink3`, `hover`, `selection`, `focus`; a 120 ms digit roll | 05 §4, §3 / 22 (A-2, A-3) |
| D-8 | Ollama JSON mode, keep-alive and warm-up | not specified | JSON mode on, keep-alive 30 min, warm-up at session start; add SPEC §16 rows | C-16 / 14 |
| D-9 | Sounds default on first run | on | follow the system's "Play feedback when volume is changed" | 05 §16 / 25 (A-8) |
| D-10 | Word for a node in person-facing copy | "node" | "step" (the root stays "the goal") | 05 §17 / 15, 17 |

All other proposed DESIGN.md amendments are in 05 §21.

## Gaps in the original brief, and how they were closed

The request asked for a friction list, the changes, a task breakdown and a design document, plus
the walkthrough. Building them surfaced six things the brief did not ask for but the work needs:

1. **A definition of success.** "Successfully use it" was made concrete as 16 timed steps with
   pass criteria (06 §3). Without it no one can say the work is done.
2. **Traceability.** Every friction entry is numbered and tracked through changes, tasks and
   verification, so a model can check its own coverage mechanically.
3. **The rules the changes must not break.** Several obvious fixes would violate CLAUDE.md (for
   example, rewording announcements or calling the model during work). Each change states its
   constraints, and the risky ones are tested.
4. **Decisions only the author can make.** Ten places where the right change contradicts an
   existing task or design rule are listed above, with a recommendation each, instead of being
   silently overridden.
5. **The model's real-world behaviour.** A cold local model and its plain-prose habit are the
   likeliest reasons the model part fails for B. They became their own changes (C-15, C-16) with a
   measurable acceptance (first phase turn on time on an M1 with a 7B model).
6. **Failure drills.** "It works when everything is fine" is not enough for rule 4; 06 §5 drills
   Ollama off, the wrong model, a model that never answers, quiet hours, the break, and the commit
   trap.

## Status

| Item | State |
|---|---|
| Documents 01–06 | Written against `main` + PR #4 |
| Tasks 12–27 | Not started |
| Author decisions D-1 to D-10 | Open |
