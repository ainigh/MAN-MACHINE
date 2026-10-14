# 01 — Operating guide: the system as it works today

A step-by-step walkthrough of the whole app, as one scenario that touches every feature. It
describes the app **as built today** (`main` plus PR #4), including its rough edges. The rough
edges are called out with ⚠ and their friction number from
[02-friction-inventory.md](02-friction-inventory.md); once the tasks in
[04-task-plan.md](04-task-plan.md) land, update this guide in the same PR as each change.

Features marked **(PR #4)** exist only once PR #4 is merged.

## The numbers used below

All times assume the default settings (SPEC §6.1–6.2, `SessionConfig.default`):

| Setting | Default | Derived |
|---|---|---|
| Round length R | 10 min | base unit q = R ÷ 2^r = 75 s (1:15) |
| Reminders r | 3 | reminders at 5:00, 2:30 and 1:15 left |
| Snoozes | up to r = 3 per round | each lasts q = 1:15 |
| Planning (STRATEGY) | q = 1:15 | |
| Away time (STATUS) | q · 2^(snoozes + 1) ÷ (items finished + 1) | 1:15 for no snooze and one finished; 2:30 for none finished |
| Grace window at Time's up | 10 s | |
| Sitting limit / movement break | 45 min / 3 min | |
| Quiet hours | 22:00–08:00 | sounds are silent then, even in a session (⚠ F-37) |
| Nudges per day | 6 | |

Test mode runs engine time 60 times faster: a 10-minute round passes in 10 seconds. It turns
itself off after 30 minutes of real time.

## The cycle in one picture

```
Start session ──► IDLE ──commit──► WORK ──Finish──────────────► STATUS ──► STRATEGY ──commit──► (sitting check)
                                    │                              ▲          │                    │
                                    └─time runs out─► TIME_UP ─────┘          └─time runs out:     ├─► WORK (next round)
                                                      │  ▲  Stop / grace       auto-commit        └─► BREAK ──► WORK
                                                      ▼  │  runs out / no snoozes left
                                                     SNOOZE (Finish → STATUS)
End session is allowed in every state.
```

---

## 0. Before the first launch (user B's Mac)

- The app is in `~/Applications/MachinePromptsMan.app`. Installing is `./install.sh` or
  `scripts/build-app.sh` (ad-hoc signed; if macOS refuses to open it, System Settings → Privacy &
  Security → Open Anyway; ⚠ F-05).
- Ollama is installed, running, and has a model pulled. Check with
  `curl -s http://127.0.0.1:11434/api/tags`, which lists the model names, e.g. `qwen2.5:7b`. Note
  the exact name: the app needs it typed (⚠ F-12).

## 1. First launch

1. Open the app. On the **very first** launch the main window appears. On every later launch,
   nothing appears except the menu-bar item (⚠ F-01): a small filled square while no session runs
   (⚠ F-02). Open the app a second time (or click the square) to get the window.
2. The menu-bar item:
   - **Left-click:** opens the main window.
   - **Right-click (or control-click):** the menu: Open Window, Start/End Session, Session
     Transcript, System Monitor, Test Mode (60×), Mute Sounds, Open at Login, Update to vX (when
     one exists), Schedule…, Settings… (⌘,), Quit (⌘Q). This menu is the only place to quit
     (⚠ F-03, F-04).
3. The window: the **session pane** on the left (state name, round, seated time, the ring with the
   countdown, Doing and Next, the buttons, the last announcement) and on the right a
   **Graph / Grid / Monitor** switch (⌘1, ⌘2, ⌘3, **PR #4**).
4. A **"Name the goal"** card asks "What is this all for?". Type the overall aim, e.g. *Ship the
   beta*, and press Return. This becomes the root of the plan (⚠ F-07).

Closing the window does not quit; the app keeps running in the menu bar and the Dock icon goes
away (⚠ F-04).

## 2. Connect the local model

The model is **off** until you turn it on (⚠ F-11).

1. Right-click the menu-bar item → **Settings…**, or press ⌘, in the main window (**PR #4**). Go to
   the **Model** tab.
2. **Model:** choose *Ollama (local)*.
3. **Endpoint:** leave `http://127.0.0.1:11434`.
4. **Model name:** replace `llama3.2` with the exact installed name, e.g. `qwen2.5:7b` (⚠ F-12).
5. Optional: **Context note**, one or two sentences about you that the model sees every turn.
   **Allow one repair pass** stays on.
6. **Save** (enabled only when something changed, **PR #4**). There is no Test button (⚠ F-13);
   you learn whether it works when the model first speaks.
7. With a model configured, a **Message** field appears in the session pane when no session runs.
   Type "Help me break down Ship the beta" and press Return. A spinner shows while it thinks; the
   reply appears under **Between rounds**. If it fails you see "The model did not answer." in red;
   hover it for the reason (⚠ F-14). The first request can be slow while Ollama loads the model
   (⚠ F-15).

## 3. Build the plan in the Graph (⌘1)

1. Select the goal (click it). Press **⌘N**: a child named "New node" appears with its title ready
   to edit. Type *Write onboarding copy*, Return. Add *Fix login bug*, *Record demo video*, and, with
   *Fix login bug* selected, ⌘N *Reproduce on Safari*. (Nothing on screen tells you about ⌘N;
   right-click → **Add Child** does the same. ⚠ F-08.)
2. **Navigate:** the arrow keys walk the tree (up = parent, down = first child, left/right =
   siblings). **Return** renames the selection; **double-click** renames too. Esc cancels a rename;
   clicking elsewhere in the graph keeps it (**PR #4**).
3. **Re-parent:** drag *Record demo video* onto *Write onboarding copy*; the drop target is
   outlined.
4. **Dependency:** right-click *Record demo video* → **Add Dependency…**, then click *Fix login bug*.
   A dashed amber arc with an arrowhead appears, and the dependent node's outline turns dashed
   amber: it is **blocked** until *Fix login bug* is done. Blocked is derived; you cannot set or
   clear it directly (⚠ F-24). Esc cancels choosing (**PR #4**).
5. **The right-click menu** on a node: Rename; Add Child; Set as Doing; Set as Next; Mark Open; Mark
   Done; Cross Out (or Restore); Add Dependency…; Remove Dependency ▸; Lock (no suggestions) /
   Unlock; Snooze Nudges Until Tomorrow / Resume Nudges; Pin / Unpin; and, only for a leaf that was
   never Doing, Next or done, **Delete Typo** (⚠ F-23). On empty canvas: Add Child, Fit.
6. **Camera:** scroll to pan (a mouse wheel works at a usable speed, **PR #4**), pinch to zoom,
   **Fit** to frame everything (eased, **PR #4**). Zoom and position are kept across relaunch and
   pane switches (**PR #4**).
7. **Hover** a node for 400 ms: full title and "updated 3d ago".
8. **Undo / redo:** ⌘Z and ⇧⌘Z, through the patch log. Not in the Edit menu (⚠ F-20). **⌘⌫** crosses
   out the selection.
9. **Refusals:** an edit the engine refuses shows a toast for 2 s with the engine's reason, which
   can include internal ids (⚠ F-21).
10. **Finished subtrees** (done or crossed out all the way down) fold into one pill with a count
    after 30 s unselected; click to expand (**PR #4** fixed folding of subtrees with open work).

## 4. Fill in details in the Grid (⌘2)

1. The tree as an indented table: Title, Status, Due, Progress, Links, Updated.
2. **Title:** edit in place; Return or leaving the cell saves; Esc restores (**PR #4**).
3. **Status:** a menu of open, doing, next, done, Cross Out / Restore (⚠ F-22).
4. **Due:** click "—" to set today, then edit the date; Clear removes it (⚠ F-25).
5. **Progress:** click the bar for a slider in steps of 5%.
6. **Links:** click the count to add URLs (Return) and open them.
7. **Quick-log** at the bottom: type a title, Return, and it is added under the selected row; the
   field stays focused for the next.
8. Selecting a row selects the node in the graph and centres it there.

## 5. Settings tour (⌘,)

- **Session:** Round length (R), Reminders per round (r), Sitting limit (Ls), Movement break (Lb),
  Grace window (G) (⚠ F-39). "Derived" shows the base unit q, snoozes per round, the reminder times
  and a table of STATUS lengths by snoozes (rows) and items finished (columns). Changes apply at the
  next session. Save / Revert.
- **Model:** see §2. The Anthropic option takes a model name and an API key (kept in the Keychain;
  the tab says whether one is stored, **PR #4**).
- **Attention:** quiet hours (from / to), nudges per day, the five rules on or off (overdue, due
  soon, stale, unblocked, drift; ⚠ F-40), and Snooze nudges for 1 hour, until tomorrow, or until
  the next session (⚠ F-43).
- **General:** Open at Login, Sounds, Test Mode (60×), log retention, Show Logs Folder, Export Store
  as JSON….

For a quick tour of the cycle, turn on **Test Mode**: a "TEST 60×" badge appears top right.

## 6. Start a session and commit

1. Press **Space** (with the main window in front and no text field focused) or click **Start
   session**. Announcement: *"Session open. Commit to start."* State: **IDLE**.
2. Choose the pair (⚠ F-26):
   - **Doing:** click the small **dot** at the left of *Reproduce on Safari*, or select it and press
     **D**.
   - **Next:** **⌥-click** the dot on *Write onboarding copy*, or select it and press **N**.
   - Rules (SPEC §6.5.1): the two must be different; each must be open, doing or next; Doing must
     have no unfinished dependencies; Next may be blocked only if what blocks it is exactly Doing.
     Picking *Record demo video* as Doing keeps Commit disabled; hover Commit for the reason, or
     press Space to see it as a toast (**PR #4**).
   - ⚠ **F-27, the trap:** do **not** use right-click → Set as Doing / Set as Next in IDLE or
     STRATEGY. Those apply a patch, and a patch that leaves both slots filled *is* a commit: the
     round starts at once, and in STRATEGY changing one slot ends planning immediately.
3. Press **Space** or **Commit**. A rising tone; *"Round 1. Reproduce on Safari doing, Write
   onboarding copy next. 10 min, starting now."* The ring empties as the round runs; the menu-bar
   digits change on the same second (**PR #4**).

## 7. Round 1: reminders, a promotion, finishing early

1. At 5:00, 2:30 and 1:15 left: a soft tick, a thin strip at the top of the pane ("5 min left."),
   and the menu-bar item flashes. With the window hidden, a system notification; macOS asks for
   permission at the first reminder (⚠ F-35).
2. Right-click *Reproduce on Safari* → **Mark Done**. The engine promotes Next: *"Now doing Write
   onboarding copy."* The round continues; finishing two items in a round is how away time
   shrinks.
3. Press **Space** (**Finish**). State **STATUS**: away time = 75 s × 2 ÷ (1 + 1) = **1:15**. The pane
   says *"Away. Back in 1:15."* and lists the round's changes ("Reproduce on Safari  open → done").
   STATUS cannot be ended early; edits you make now are your status report (⚠ F-30). If a model is
   configured, it is asked now, once, in the background; nothing it says is shown yet.

## 8. STRATEGY: the model's output and proposals

1. At the end of STATUS: **STRATEGY**, 1:15. Under **Between rounds**:
   - the model's words;
   - a question if it asked one, with an Answer field (your reply is routed as the answer);
   - **proposals**: each op as a row ("add “Write FAQ” under “Write onboarding copy”"), **Accept**
     per row when there are several, **Accept all**, **Reject** (remembered for 14 days so it is
     not proposed again), and **Lock** (reject and stop all suggestions for those nodes; ⚠ F-45).
     If the plan changed since the proposal, it says *"The map changed since this was proposed."*
     and blocks the affected rows.
2. In the graph, proposals are **ghosts**: new nodes at 50% with dashed outlines, a status change as
   a second outline in the proposed colour, a move as a dashed edge to the proposed parent. Hover a
   ghost for what the model said; click it to open that proposal's card.
3. The **Message** field sends now in STRATEGY (and in IDLE or with no session); in other states a
   message waits for the next STRATEGY.
4. Let STRATEGY run out on purpose: *"No choice made. Write onboarding copy doing, Fix login bug
   next."* That is the auto-commit (SPEC §6.7): keep the slots if set, else the oldest open nodes.
   Undecided proposals expire and are **not** remembered as rejected. Then the sitting check runs,
   and round 2 starts (⚠ F-32).

## 9. Round 2: Time's up, snoozes, Stop

1. Let the 10 minutes run out. Two falling tones; a **"Time's up."** card in the middle of the
   screen, above other windows, its red border pulsing once a second, a 1 px bar along the bottom
   counting the 10 s grace window.
2. Click **Snooze · 1:15 · 3 left** (or press Space if the main window is in front; keys do nothing
   on the card itself, ⚠ F-29). *"Snooze 1 of 3. 1:15."*
3. When the snooze ends the card returns. Snooze again (*"Snooze 2 of 3."*).
4. Press **Esc** (main window in front) or click **Stop**: the card shows **"Stop."** in red for 2 s
   and closes; a low tone.
   - A fourth snooze would be refused: *"No snoozes left. Stop."*
   - Letting the grace window run out is a stop (⚠ F-36).
   - A snooze after the grace window: *"Too late. Stop."*
5. STATUS is now 75 × 2³ ÷ 1 = **10 min**: two snoozes and nothing finished (⚠ F-31). Because 10 min
   is at least the 3-minute break, the app assumes you moved and resets the sitting clock.

## 10. The sitting limit and the movement break

1. Before each round the engine checks: seated time + 10 min > 45 min?
2. When it is: *"Seated 38 min. Movement break, 3 min."* A teal band across the top of the screen
   with a countdown. It blocks no clicks, but the plan is locked: edits are refused (⚠ F-33). The
   break cannot be ended early.
3. At the end: *"Sitting clock reset."* and the next round starts.

## 11. End the session

- **End session** (small, bottom of the pane) or right-click → **End Session**. No confirmation
  (⚠ F-34). Cards and the band close; the menu bar returns to the square.
- **Session Transcript** (right-click menu) lists every announcement with its time since the
  session started.

## 12. Between sessions: nudges, messages and the schedule

1. With no session running, the app evaluates five **initiative rules** at launch and every 15
   minutes:
   - **overdue:** due date passed, not done;
   - **due soon:** due within 3 days;
   - **stale:** Doing or Next untouched for 7 days;
   - **unblocked:** all of a node's dependencies just finished;
   - **drift:** no progress change on Doing for 5 days.
   A hit may wake the model to word a nudge, but only outside quiet hours, within the daily budget,
   and not while nudges (or that node) are snoozed. During a session the rules never wake the
   model; their hits go into the next STATUS request instead.
2. **Schedule…** (right-click menu) lists upcoming entries and lets you add one ("tomorrow 09:00 —
   review the beta checklist"). The model can schedule follow-ups too (its `next`), within the same
   policy. An entry due during a session waits for the session to end.

## 13. The Monitor (⌘3) and the problems badge

- **Diagram:** nine parts (Timers, Screen and sound; You, Session engine, Turns, Model; Store, Disk,
  Initiative). A dot travels an edge for each hand-off; an arc on a part shows work in progress
  (for a model turn, against its deadline, amber once past it); each part shows its last outcome
  and unseen problems.
- **Problems badge:** in other panes, unseen warnings or errors show a capsule such as "2 problems"
  beside the switch; clicking it opens the Monitor (⚠ F-42).
- **Inspector:** the event list (click a part to filter, Problems only, Mark seen) and the detail of
  the selected event, including the model's prompt and raw output.
- **Drill:** set the Ollama endpoint to a port nothing listens on. The turn misses its deadline,
  the monitor shows it, and the session carries on unaffected (CLAUDE.md rule 4).

## 14. Housekeeping

- **Mute Sounds** silences all four sounds. Quiet hours also silence them (⚠ F-37).
- **Open at Login** is off by default.
- **Update to vX** appears in the right-click menu when a newer GitHub release exists; it installs
  in place and relaunches. The plan lives in `~/Library/Application Support/MachinePromptsMan/`,
  outside the app, and is saved after every change (⚠ F-49).
- **Export Store as JSON…** (General) writes the whole plan and its history to a file.

---

## Keyboard reference

These work only when the main window is in front and no text field has focus (⚠ F-29).

| Key | Action |
|---|---|
| Space | Finish (WORK, SNOOZE) · Snooze (TIME_UP) · Commit (IDLE, STRATEGY) · Start session (none) |
| Esc | Stop at Time's up · cancel choosing a dependency (**PR #4**) · cancel a rename |
| D / N | The selected node becomes Doing / Next for the commit (IDLE, STRATEGY) |
| ⌘N · ⌘⌫ | New child of the selection · Cross out the selection |
| ⌘Z · ⇧⌘Z | Undo · Redo |
| ⌘1 ⌘2 ⌘3 | Graph, Grid, Monitor (**PR #4**) |
| ⌘, | Settings (**PR #4** in the main window; always from the menu-bar menu) |
| Arrows · Return | Walk the tree · Rename the selection (Graph) |

## Glossary

| Word on screen | Meaning |
|---|---|
| Goal | The root of the plan. Cannot be moved, crossed out or deleted. |
| Node | One step of the plan. |
| Doing / Next | The two slots: what you work on this round, and what comes after it. |
| Commit | Confirm Doing and Next and start the round. |
| WORK | A round in progress. |
| TIME UP | The round's time ran out; snooze or stop within the grace window. |
| SNOOZE | A short extension of the round. Each one doubles the away time that follows. |
| STATUS | Away time after a round. Its length depends on snoozes and items finished. Edits made now are the status report. |
| STRATEGY | The short planning window before the next round. The model's output appears here. |
| SIT CHECK | The instant check of seated time between rounds. |
| BREAK | The movement break. The plan is locked; it cannot be skipped. |
| Seated | Continuous time at the desk this session. |
| Between rounds | The area where the model's words, question and proposals appear. |
| Proposal | A change the model suggests. Nothing applies until you accept it. |
| Lock | Stop the model from ever suggesting changes to a node. |
| Crossed out | Dropped, kept in history. |
| Blocked | Waiting on unfinished dependencies (derived, not set). |
