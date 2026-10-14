# 06 — Verification protocol: proving a newcomer succeeds

The changes in [03](03-required-changes.md) are only done when a person who has never seen the app
succeeds with it alone. This protocol is how to show that. Task 26 runs it in full; run it
informally after milestone M1 too.

## 1. The machine

Prepare exactly B's situation:

1. A Mac on macOS 14 or newer, signed in to a normal (non-admin is fine) account.
2. Machine Prompts Man installed in `~/Applications` with `install.sh` or `scripts/build-app.sh`, but
   **never launched** on this account. Confirm there is no
   `~/Library/Application Support/MachinePromptsMan/` folder; delete it if there is.
3. Ollama installed, its app running (menu-bar llama icon), and one model pulled, for example
   `ollama pull qwen2.5:7b`. Confirm `curl -s http://127.0.0.1:11434/api/tags` lists it. Do **not**
   preload the model (B's first request must be the cold one).
4. Sound on at a normal level. Notifications in their default state. The time of day outside quiet
   hours (08:00–22:00), unless running the quiet-hours check in §5.
5. Screen recording running (QuickTime or `screencapture -v`), with the menu bar visible.

## 2. The participant

- Has never seen the app, its docs or this repository.
- Uses a Mac day to day.
- Is told only: "This app helps you work in timed rounds. Use it to plan three small things you
  could do now and work through at least two rounds. Think aloud. I will not help."
- The observer does not answer questions. If the participant is stuck for 3 minutes on one step,
  the step fails; the observer notes where and then gives the smallest hint that unblocks them.

## 3. The steps and their pass criteria

Time each step from the end of the previous one. Settings are defaults; real time, not test mode.

| # | Step | Pass when | Time limit | Closes |
|---|---|---|---|---|
| 1 | Open the app from Finder | The window is visible without a second launch | 30 s | F-01, F-02 |
| 2 | Understand what it is | Participant can say, in their words, "rounds of work with breaks, and I choose what to do" after the first-run guide | 2 min | F-07, F-09 |
| 3 | Name a goal and add three steps | Goal plus three child steps exist | 2 min | F-08 |
| 4 | Turn the local model on | Participant accepts the offered model in the guide, or finds it in Settings; Settings → Model shows it selected | 2 min | F-11, F-12 |
| 5 | Start a session and choose Doing and Next | Round 1 starts with the participant's chosen pair, and only when they meant it to | 2 min | F-26, F-27, F-28 |
| 6 | Work through round 1 and finish it early | Participant presses Finish (or Space) before time is up | the round | F-29, F-30 |
| 7 | Understand STATUS | Participant says they are meant to step away, and why it lasts as long as it does | during STATUS | F-30, F-31 |
| 8 | Read the model's message between rounds | The model's `say` is on screen in STRATEGY; participant reads it aloud | STRATEGY | F-15, F-17 |
| 9 | Act on one proposal | Participant accepts or rejects at least one proposal row, and can say what it did | STRATEGY | F-45 |
| 10 | Choose the next pair before planning runs out, or knowingly let it run out | Participant states what will happen if they do nothing, before it happens | STRATEGY | F-32 |
| 11 | Let round 2 run out and use one snooze | Participant snoozes once from the Time's-up card, then stops | round 2 | F-29, F-31, F-36 |
| 12 | Edit the plan: rename one step, mark one done, add a dependency | All three done; no refusal toast left unread | 3 min | F-18, F-21, F-24 |
| 13 | Find the keyboard shortcut for New Step | Participant finds it in a menu or Help | 1 min | F-19 |
| 14 | End the session | Participant ends it, deliberately, with no accidental end earlier | 1 min | F-34 |
| 15 | Close the window, then quit the app | Participant closes the window, knows it is still running, and quits | 1 min | F-03, F-04 |
| 16 | Reopen and find yesterday's plan | Plan is there; participant says it was saved | 30 s | F-01, F-49 |

**Overall pass:** every step passes for every participant, with no hint given.

## 4. The model run

During steps 6–9, record from the app's logs (`Settings → General → Show Logs Folder`):

- `turn-log.jsonl`: the phase turn for round 1 (`"trigger"` starts with `phase`) has
  `"deadlineMet": true`; note its `latencyMs`, `ladderStep` (1 = fenced envelope, 3 = bare JSON,
  5 = prose only) and `outcome`.
- `system-log.jsonl`: one "warm-up" line at session start (task 14), and no `adapter` line saying a
  turn started while the state was WORK, TIME_UP, SNOOZE or BREAK (CLAUDE.md rule 3; read the
  `transition` lines around each `adapter` line).

**Pass:** the phase turn met its deadline on the cold model, and the rule-3 search finds nothing.

## 5. Failure drills (observer only, after the participant leaves)

Each drill starts from a fresh session in test mode (developer tools on) to save time.

| Drill | How | Pass when |
|---|---|---|
| Ollama not running | Quit the Ollama app; run a round | Round completes; STRATEGY shows "Ollama is not running." with "Model settings…" and "Turn off the model"; after two rounds the badge reads "Model not reachable" |
| Wrong model name | Settings → Model → Other… → `nope:1b`; run a round | STRATEGY shows "The model nope:1b is not installed in Ollama." |
| Model never answers | `nc -lk 11999`; endpoint `http://127.0.0.1:11999`; run three rounds | Every round runs normally; the app stays responsive; the turn log shows missed deadlines and abandons; the next turn still starts (PR #4 fix) |
| Quiet hours | Set quiet hours to cover now; start a session | "Sounds quiet until …" is visible; sounds follow the setting from task 20 |
| Movement break | Set the sitting limit to 12 min and round length to 5 min | The round before the break warns; during the break edits explain the lock with the time left |
| Accidental commit | In STRATEGY, use the context menu Set as Next on another node | STRATEGY continues; only Commit or Space ends it |
| Relaunch mid-session | Quit during WORK; reopen | The session is ended cleanly on launch (as today) and the plan is intact |

## 6. Automated checks (run in CI or locally)

- `swift test` on Linux and macOS: all tests green, including every test named in
  [04-task-plan.md](04-task-plan.md).
- A grep gate, added in task 17, that fails the build if person-facing strings contain a node id
  pattern (`n_[0-9A-Z]{4,}`) or a raw spec symbol label: run
  `scripts/check-strings.sh` (to be written in task 17) over `Sources/MachinePromptsMan/UI/Strings.swift`.

## 7. Results table (paste into the task 26 PR)

| Step | Participant 1 | Participant 2 | Notes |
|---|---|---|---|
| 1 | pass / fail, time | pass / fail, time | |
| … | | | |
| 16 | | | |
| Model run | | | latency, ladder step |
| Drills | | | one line each |

Attach the recordings. For every fail, link the fix PR.
