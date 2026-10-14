# 02 — Friction inventory: everything that resists a first-time user

**The person.** User B has never heard of the app. They are handed a Mac with Machine Prompts Man
installed in `~/Applications`, Ollama installed and running, and one local model already pulled
(for example `qwen2.5:7b`). Nobody explains anything. Success means: within one sitting, B plans a
few pieces of work, runs at least two full rounds, gets a useful word from the local model between
rounds, and ends the session — without outside help.

**What this list is.** Every point where the current system works against B, found by reading the
code and the spec, not by guessing. Each entry says what B experiences, why it happens (with the
file and symbol, so a builder can find it), and how bad it is. The fixes are in
[03-required-changes.md](03-required-changes.md); each change cites the F-numbers it closes.

**Baseline.** `main` at `fe012b2`, which includes PR #4 (UI polish and host fixes). Where PR #4 already changed something,
the entry says so. Line numbers drift; symbol names do not, so search by symbol.

**Severity.**

| Level | Meaning |
|---|---|
| **Blocker** | B cannot get past this without outside help, or gives up. |
| **Major** | B gets past it, but with confusion, a wrong action, or lost work or time. |
| **Minor** | B notices it; it costs polish and trust, not progress. |

**Count.** 50 entries: 8 Blocker, 26 Major, 16 Minor.

---

## A. Finding the app and staying oriented

### F-01 — Nothing appears when the app is opened (after the first time). **Blocker**
- **B experiences:** double-clicks the app; no window, no Dock icon. Thinks it failed to launch.
- **Why:** it is a menu-bar app (`LSUIElement` in `scripts/build-app.sh`). `AppModel.start(fresh:)`
  shows the main window only when the store was just created (`persistence.createdFresh`). On every
  later launch the only sign of life is the menu-bar item. A second double-click does open the
  window (`applicationShouldHandleReopen`), but B has no reason to try.

### F-02 — The idle menu-bar item is a tiny square with no text. **Blocker**
- **B experiences:** cannot find the app in the menu bar. On a MacBook with a notch and several
  menu-bar items, the item may sit behind the notch and be invisible.
- **Why:** `MenuBarDisplay.make` returns `.square` with `digits: nil` when no session runs
  (`Host/Presentation.swift`); `MenuGlyph` draws a 14 pt filled rounded square (`UI/MenuBar.swift`).
  Nothing names the app.

### F-03 — Half the app is behind a right-click nobody mentions. **Major**
- **B experiences:** left-clicks the menu-bar item and gets the window. Never discovers Settings,
  Schedule, Transcript, Test Mode, Mute or Quit, which are only in the right-click menu.
- **Why:** `StatusItemController.clicked` opens the window on left-click and builds the menu only on
  right-click or control-click.

### F-04 — Closing the window makes the app vanish, and there is no visible way to quit. **Major**
- **B experiences:** closes the window; the Dock icon disappears; B believes the app quit. Later, a
  "Time's up." card appears from nowhere. Or B wants to quit and cannot find how.
- **Why:** `MainWindowDelegate.windowWillClose` returns the app to `.accessory`. Quit lives only in
  the right-click menu (F-03). The app menu that appears while the window is open is the default
  SwiftUI one and is never explained.

### F-05 — First open can be blocked by Gatekeeper. **Minor (conditional)**
- **B experiences:** if the app arrived with a quarantine flag (downloaded through a browser),
  macOS says it cannot verify the developer, and B stops.
- **Why:** the app is ad-hoc signed, not notarized (`scripts/build-app.sh`, README "Install"). In
  B's scenario the app was installed for them, so this only bites if it was installed by download.

### F-06 — The app has two names. **Minor**
- **B experiences:** "MachinePromptsMan" in the app menu, Finder and Activity Monitor; "Machine
  Prompts Man" in the window, notifications and menus.
- **Why:** `CFBundleName` is `MachinePromptsMan` in `scripts/build-app.sh`; `Strings.appName` is
  `"Machine Prompts Man"`. There is no `CFBundleDisplayName`.

---

## B. First run: understanding what this is

### F-07 — The first screen asks for a "goal" with no context. **Major**
- **B experiences:** a card says "Name the goal" / "What is this all for?". B does not know whether
  this is a project, a day, or a life goal, or what happens next. There is no skip.
- **Why:** `GraphView.overlays`, `goalNeedsName` in `AppModel`. The root node is the whole tree's
  goal (`Store(rootTitle:)`), but nothing says so.

### F-08 — After naming the goal, nothing says how to add work. **Blocker**
- **B experiences:** one pill in an empty canvas. No button, no hint. B does not know about ⌘N,
  right-click → Add Child, or the Grid's quick-log field.
- **Why:** the graph has no visible add affordance and no empty-state copy (`GraphView`).
  `Strings.noSessionHint` exists but is used nowhere.

### F-09 — Nothing explains how the system works. **Blocker**
- **B experiences:** sees "NO SESSION", a ring, "Doing — / Next —", "Start session". Has no idea
  that work comes in timed rounds, that each round needs a Doing and a Next, that there is a forced
  away-time after each round, a short planning window, and a movement break every ~45 minutes.
- **Why:** the concepts live in `SPEC.md` and `DESIGN.md`, which are for builders. The app has no
  help window, and its Help menu is the default "Help isn't available".

### F-10 — The screen speaks the spec's vocabulary. **Major**
- **B experiences:** "IDLE", "STATUS", "STRATEGY", "SIT CHECK", "Commit", "Seated 12 min",
  "Between rounds", "Status, 1:15." These are precise words to the author and opaque to B.
- **Why:** `Strings.stateName`, `Strings.commit`, `Strings.seated`, `Strings.fromTheModel`; the
  announcements are engine strings (`Announcement.text`) and must not be reworded (CLAUDE.md rule
  6), so the explanation has to come from somewhere else.

---

## C. Connecting the local model

### F-11 — The model is off by default, and nothing says one could be on. **Blocker**
- **B experiences:** uses the app for a whole session; the model never says anything. B does not
  know the app has a model at all, let alone that Ollama is sitting there ready.
- **Why:** `ModelSettings.kind` defaults to `.none` (`Host/Model/ModelAdapter.swift`). There is no
  detection of a local Ollama server and no first-run prompt. The model settings are reachable
  only through right-click → Settings… → Model (F-03).

### F-12 — The Ollama model name must be typed, and the default is probably wrong. **Blocker**
- **B experiences:** chooses "Ollama (local)", leaves "llama3.2", saves. Every turn fails because
  the installed model is something else. The only sign is "The model did not answer." in red.
- **Why:** `ModelSettings.ollamaModel = "llama3.2"`; `ModelSettingsView` uses a free `TextField`.
  Ollama answers HTTP 404 "model not found", surfaced only through `coordinator.failure` in a hover
  tooltip (`HeldCardView`). Ollama's own `GET /api/tags` would list the installed models.

### F-13 — There is no way to test the connection. **Major**
- **B experiences:** saves settings and has to start a session, finish a round and wait for
  STRATEGY to learn whether the model works. If Ollama is not running, the same red line appears.
- **Why:** `ModelSettingsView` has only Save. No probe, no success state, no "Ollama is not running"
  diagnosis.

### F-14 — When the model fails, the reason is hidden and there is no remedy. **Major**
- **B experiences:** "The model did not answer." Hovering (if B thinks to) shows "HTTP 404: …" or a
  URL error. Nothing says what to do.
- **Why:** `HeldCardView` shows `Strings.modelFailed` with `.help(coordinator.failure)`. The
  Monitor has the detail but is a developer tool (F-41).

### F-15 — A local model's first answer is slow and can miss the window. **Major**
- **B experiences:** the first round ends; STATUS is short; the model's answer has not arrived when
  STRATEGY opens. B sees nothing, or sees it next time, out of context.
- **Why:** the first request makes Ollama load the model into memory (often 5–30 s on a laptop).
  The phase turn's deadline is the end of STATUS (`ModelTurnCoordinator.start`), which is
  `q·2^(z+1)/(x+1)`: 1:15 by default for a one-node round, ~37 s if three nodes were cleared. A
  late answer is kept only as proposals; its `say` is lost (SPEC §8.6). The adapter sends no
  `keep_alive`, so Ollama may unload the model again between rounds (its default is 5 minutes).

### F-16 — Small local models often answer in prose, and B gets fewer proposals. **Major**
- **B experiences:** the model talks but never proposes changes to the plan.
- **Why:** `OllamaAdapter.complete` sends `{"model","prompt","stream":false}` only. It does not ask
  for JSON output (`"format": "json"`), which Ollama supports and SPEC §9.4 allows adapters to use
  internally. The degradation ladder (SPEC §9.3) then falls to prose-only: `say` survives, `patch`
  is empty.

### F-17 — Where and when the model talks is invisible. **Major**
- **B experiences:** does not know to look under "Between rounds" in the left pane, or that the
  model speaks only between rounds and when no session runs. The Message field appears only after
  a model is configured, and is hidden during a round, with no explanation of why it went away.
- **Why:** `SessionPaneView.content` shows `HeldCardView` only when the state is nil, IDLE or
  STRATEGY; `HeldCardView` shows the field only if `coordinator.hasModel`. This is SPEC §8.6 by
  design ("the model is silent during work"); the design is right, the silence is unexplained.

---

## D. Building the plan

### F-18 — Editing the graph happens through hidden gestures. **Major**
- **B experiences:** cannot find how to set a status, cross out, add a dependency, or lock a node.
  Everything is in the right-click menu or a keyboard shortcut, and nothing points to either.
- **Why:** `GraphView.menuItems`; there is no toolbar or inspector. DESIGN §8 lists right-click as
  the op menu.

### F-19 — The keyboard shortcuts are documented nowhere in the app. **Major**
- **B experiences:** never learns Space, D, N, ⌘N, ⌘⌫, ⌘Z, the arrow keys or Return, which are the
  fastest way to use the app.
- **Why:** `AppModel.handleKey` intercepts keys through a local event monitor. No menu item
  carries the key equivalents, so macOS cannot show them, and there is no shortcut sheet.

### F-20 — Undo and redo are not in the Edit menu. **Minor**
- **B experiences:** reaches for Edit → Undo; it is greyed out or does nothing to the plan.
- **Why:** undo runs through `SessionController.undo()` from `handleKey`; the SwiftUI default Edit
  menu is wired to `NSUndoManager`, which the app does not use.

### F-21 — Refusals are shown for 2 seconds, in engine language, with internal ids. **Major**
- **B experiences:** a toast flashes something like "cannot set doing on n_01J8Z… (done)" or
  "that dependency would block the doing node n_01J…" and vanishes before B reads it.
- **Why:** `AppModel.perform` shows `"\(error)"` (`ValidationError.description` in
  `MpmCore/Store.swift`) for `Theme.Motion.toast` (2 s). tasks/05 asked for the engine's reason
  verbatim; that serves the author, not B.

### F-22 — Status words are raw enum values. **Minor**
- **B experiences:** the Grid's status menu reads "open", "doing", "next", "done", "crossed out",
  lowercase.
- **Why:** `Strings.statusWord` returns `Status.rawValue`.

### F-23 — "Delete Typo", and why most nodes cannot be deleted. **Minor**
- **B experiences:** wants to delete a node; finds "Cross Out" and sometimes an odd "Delete Typo".
  Does not know why delete appears for some nodes and not others.
- **Why:** removal is allowed only for leaves that never held a slot or were done
  (`store.everHeldSlotOrDone`), by design (the log keeps history). Not explained.

### F-24 — "Blocked" cannot be set or cleared directly, and why is unexplained. **Minor**
- **B experiences:** sees a dashed amber outline, tries to unblock the node, cannot.
- **Why:** blocked is derived from unfinished dependencies (SPEC §3.1); `ValidationError.cannotSetBlocked`.
  The hover tooltip says nothing about what blocks the node.

### F-25 — Some Grid edits are fiddly. **Minor**
- **B experiences:** clicking "—" in Due sets *today* at once; progress is a 2 pt line to click.
- **Why:** `DueCell` and `ProgressCell` in `UI/GridView.swift`.

---

## E. Starting a session and choosing what to work on

### F-26 — Choosing Doing and Next is undiscoverable. **Blocker**
- **B experiences:** presses Start session, sees "Commit" greyed out, Doing "—", Next "—". Cannot
  work out how to fill them. The reason is only in a hover tooltip on the disabled button (and,
  since PR #4, in a toast when Space is pressed).
- **Why:** slots are picked by clicking an 8 pt dot inside a pill (Doing), ⌥-clicking it (Next), or
  pressing D / N with a node selected (`GraphView.click`, `AppModel.handleKey`). None of these are
  shown. The Grid has no way to pick at all.

### F-27 — "Set as Doing/Next" from the right-click menu commits without asking. **Blocker**
- **B experiences:** in IDLE, uses the menu to set a node as Doing, then another as Next, and the
  round starts at once, before B pressed anything. In STRATEGY, where the previous round's Doing
  and Next are still set, choosing *one* new slot from the menu ends the planning window
  immediately. Undo cannot reverse it.
- **Why:** these menu items apply a patch (`GraphView.menuItems` → `.setStatus(id, .doing)`).
  `Engine.applyPatch` treats any patch in IDLE or STRATEGY that leaves both slots filled and
  changed as a commit (SPEC §6.5 note), and slots persist across rounds and sessions. Undo history
  is then cleared (`SessionController.apply`, PR #4). The engine rule is frozen and right for the
  model and for power use; the menu wiring is what surprises B.

### F-28 — Two mechanisms fill the same two rows. **Major**
- **B experiences:** the Doing/Next rows sometimes show what B picked (dots) and sometimes the
  node's status; picks vanish when a round starts; statuses set from the Grid behave differently
  from picks in the Graph.
- **Why:** `SessionPaneView.slots` shows `model.commitDoing` (pick, else current slot) in IDLE and
  STRATEGY, `store.doing` otherwise; the Grid status menu applies patches (F-27 applies there too).

### F-29 — Space does everything, and nothing says so. **Major**
- **B experiences:** never finds that Space finishes, snoozes, commits and starts. When another
  app is in front and the Time's-up card appears, Space and Esc do nothing.
- **Why:** `AppModel.handleKey` only runs when the main window is key and no text field has focus.
  The Time's-up panel is non-activating (`CardsController.panel`) and never key.

---

## F. Living through the round cycle

### F-30 — "Away. Back in 1:15." does not say what B should do. **Major**
- **B experiences:** the round ends; the pane says "STATUS" and "Away." B does not know whether to
  wait, report, or leave the desk; cannot end it early; does not know why.
- **Why:** SPEC §6.5 notes: STATUS cannot be ended early and is "the cost of the round and the away
  time"; edits made during it *are* the status report. `SessionPaneView.controls` shows only
  `Strings.away`.

### F-31 — Snoozing has a cost B cannot see. **Major**
- **B experiences:** snoozes freely ("Snooze · 1:15 · 3 left"), then gets a 10-minute STATUS and
  does not know why it is so long.
- **Why:** STATUS length is `q·2^(z+1)/(x+1)` (SPEC §6.2): each snooze doubles the away time;
  each cleared node divides it. Nothing shows this at the moment of choosing.

### F-32 — The planning window is short and ends by itself. **Major**
- **B experiences:** reads the model's message, starts thinking, and the app picks for them: "No
  choice made. X doing, Y next." B feels the app took control.
- **Why:** STRATEGY lasts `q` (1:15 by default) and then auto-commits (SPEC §6.7). The ring shows
  time, but nothing says "choose before this runs out, or I keep the current pair".

### F-33 — The movement break arrives unannounced and locks the plan. **Major**
- **B experiences:** about 40 minutes in, a teal band appears and edits fail with "not available
  during a movement break". B did not know a break was coming or that it cannot be skipped.
- **Why:** SIT_CHECK (SPEC §6.6.2, §6.8). There is no warning in the round before, and the toast is
  the engine's reason (F-21).

### F-34 — "End session" ends at once, with no confirmation. **Major**
- **B experiences:** clicks the small "End session" link at the bottom by mistake and loses the
  session (the round count, seated time, held model output).
- **Why:** `SessionPaneView` sends `.endSession` directly; the menu-bar item does the same.

### F-35 — The notification permission prompt interrupts the first round. **Minor**
- **B experiences:** the first reminder triggers a macOS permission dialog in the middle of work.
- **Why:** `AppModel.announced` asks on the first reminder (tasks/11 asked for exactly that).

### F-36 — The Time's-up grace window is 10 seconds. **Minor**
- **B experiences:** looks away, comes back, and the card has flipped to "Stop." — the snooze B
  wanted is gone.
- **Why:** `G = 10 s` (SPEC §6.1 default); lapsing counts as stop (SPEC §6.5). Correct by spec;
  unexplained to B.

### F-37 — Late in the evening, the app goes silent without saying why. **Major**
- **B experiences:** works at 22:30; reminders and Time's up make no sound. B thinks sound is
  broken.
- **Why:** `AppModel.quietNow` mutes every tone during quiet hours (default 22:00–08:00, tasks/10:
  "quiet hours respected for sounds too"), including inside a session B chose to run. Nothing on
  screen says sounds are quiet.

### F-38 — There is no voice. **Minor**
- **B experiences:** with the window hidden and notifications declined, a reminder is one soft tick.
- **Why:** SPEC §10 treats spoken announcements as first-class; no TTS is wired (CLAUDE.md mentions
  the reference app's approach). Out of scope for first-run success, listed for completeness.

---

## G. Settings and the out-of-session features

### F-39 — Settings are written in formula symbols. **Major**
- **B experiences:** "Round length (R)", "Reminders per round (r)", "Base unit q", a table headed
  "z \ x", "Grace window (G)", "Changes apply at the next session."
- **Why:** `Strings` in the Settings section mirror SPEC §6.1–6.2.

### F-40 — Nudge rules have names and no explanation, and their thresholds are hidden. **Minor**
- **B experiences:** toggles called "overdue", "due soon", "stale", "unblocked", "drift". What is
  stale? After how long?
- **Why:** `RulesAndSnooze` shows `InitiativeScheduler.ruleNames` with underscores replaced. The
  thresholds (`dueSoonDays` 3, `staleDays` 7, `driftDays` 5 in `MpmCore/Ops.swift` `Settings`) are not
  editable or shown.

### F-41 — Developer tools sit next to everyday controls. **Major**
- **B experiences:** a "Monitor" tab beside Graph and Grid that shows nine boxes named "Session
  engine", "Turns", "Store"; "Test Mode (60×)" and "System Monitor" in the menu.
- **Why:** DESIGN §12 put the Monitor in the main segmented control; Test Mode is in the menu-bar
  menu and in General settings (tasks/10).

### F-42 — A "problems" badge appears and leads somewhere technical. **Major**
- **B experiences:** after the model misses a deadline, "1 problem" appears top right. Clicking it
  shows a diagram and event names like "turn abandoned". Alarming and not actionable.
- **Why:** `MainView` shows `monitor.unseenTotal`; every warning or error counts, including
  expected ones like a late local model.

### F-43 — Three different "snooze" features. **Minor**
- **B experiences:** "Snooze" on Time's up (extend the round), "Snooze nudges" in Attention, and
  "Snooze Nudges Until Tomorrow" on a node. Easy to confuse.
- **Why:** SPEC uses "snooze" for both the session extension and the attention snooze (§8.3 says
  so). The UI repeats the word.

### F-44 — Two different Settings windows. **Minor**
- **B experiences:** the app menu's "Settings…" opens one window; the menu-bar "Settings…" opens
  another, identical one. They can both be open.
- **Why:** `MachinePromptsManApp` declares a SwiftUI `Settings` scene, and `AppModel.showSettings`
  opens an aux window. PR #4 routes ⌘, in the main window to the aux one; the app-menu item still
  opens the scene.

### F-45 — Proposals offer Lock without saying what it means, and no per-row Reject. **Major**
- **B experiences:** "Accept all", "Reject", "Lock". B does not know that Lock stops all future
  suggestions for those nodes. Cannot reject one row of a multi-row proposal.
- **Why:** `ProposalCard` (`UI/HeldCard.swift`); `Strings.lockHelp` is only a tooltip. DESIGN §6
  asks for Accept / Reject per row; the coordinator has no per-op reject.

### F-46 — Test mode is easy to turn on and hard to recognise. **Minor**
- **B experiences:** toggles "Test Mode (60×)" out of curiosity; rounds end in 10 seconds; a small
  "TEST 60×" badge is the only sign.
- **Why:** `Strings.testMode` in the main menu; the badge in `MainView`.

### F-47 — The out-of-session model features are invisible. **Major**
- **B experiences:** never learns that the app can nudge about overdue or stale work, keep a
  schedule, or answer messages between sessions.
- **Why:** the Schedule window is reachable only through right-click; the message field only after
  configuring a model (F-11, F-17); nudges arrive only if a model is configured.

### F-48 — Undo is silently cleared at every commit. **Minor**
- **B experiences:** presses ⌘Z after a round starts; nothing happens; no explanation.
- **Why:** `SessionController.reduce` and (PR #4) `apply` clear history when the engine changes the
  map or the session state; this is logged to the system log only.

### F-49 — Nothing tells B where their data is or that it is safe. **Minor**
- **B experiences:** wonders whether closing the window loses the plan, or what happens on quit.
- **Why:** the store autosaves to `~/Library/Application Support/MachinePromptsMan/`
  (`Persistence`); the app never says so outside General → Show Logs Folder.

### F-50 — Recovering from a model that keeps failing is only possible from Settings. **Major**
- **B experiences:** the model fails every round; red text every STRATEGY; no "turn off" or "fix"
  next to the message.
- **Why:** `HeldCardView` offers no action next to `Strings.modelFailed`.

---

## Summary table

| ID | Title | Severity | Stage |
|---|---|---|---|
| F-01 | Nothing appears when opened | Blocker | A |
| F-02 | Idle menu-bar item is a tiny square | Blocker | A |
| F-03 | Right-click-only menu | Major | A |
| F-04 | Closing the window makes the app vanish; no visible Quit | Major | A |
| F-05 | Gatekeeper on first open | Minor | A |
| F-06 | Two app names | Minor | A |
| F-07 | Goal card without context | Major | B |
| F-08 | No hint how to add work | Blocker | B |
| F-09 | No explanation of the system | Blocker | B |
| F-10 | Spec vocabulary on screen | Major | B |
| F-11 | Model off by default, Ollama not detected | Blocker | C |
| F-12 | Ollama model name typed, wrong default | Blocker | C |
| F-13 | No connection test | Major | C |
| F-14 | Model failure hidden, no remedy | Major | C |
| F-15 | Cold local model misses the window | Major | C |
| F-16 | Prose-only answers, no JSON mode | Major | C |
| F-17 | Model's place and timing invisible | Major | C |
| F-18 | Graph editing hidden in gestures | Major | D |
| F-19 | Shortcuts undocumented | Major | D |
| F-20 | Undo not in Edit menu | Minor | D |
| F-21 | 2 s refusals with internal ids | Major | D |
| F-22 | Raw status words | Minor | D |
| F-23 | "Delete Typo" and deletion rules | Minor | D |
| F-24 | Blocked unexplained | Minor | D |
| F-25 | Fiddly Grid edits | Minor | D |
| F-26 | Picking Doing/Next undiscoverable | Blocker | E |
| F-27 | Menu "Set as Doing/Next" commits without asking | Blocker | E |
| F-28 | Two mechanisms for the slots | Major | E |
| F-29 | Space undocumented; dead on the card | Major | E |
| F-30 | STATUS does not say what to do | Major | F |
| F-31 | Snooze cost invisible | Major | F |
| F-32 | Short planning window ends itself | Major | F |
| F-33 | Break unannounced, plan locked | Major | F |
| F-34 | End session without confirmation | Major | F |
| F-35 | Permission prompt mid-round | Minor | F |
| F-36 | 10 s grace | Minor | F |
| F-37 | Quiet hours silence a chosen session | Major | F |
| F-38 | No voice | Minor | F |
| F-39 | Settings in formula symbols | Major | G |
| F-40 | Rule names unexplained, thresholds hidden | Minor | G |
| F-41 | Developer tools beside everyday controls | Major | G |
| F-42 | Technical "problems" badge | Major | G |
| F-43 | Three snoozes | Minor | G |
| F-44 | Two Settings windows | Minor | G |
| F-45 | Lock unexplained, no per-row Reject | Major | G |
| F-46 | Test mode easy to trip | Minor | G |
| F-47 | Out-of-session features invisible | Major | G |
| F-48 | Undo cleared silently | Minor | G |
| F-49 | Data location and safety unstated | Minor | G |
| F-50 | No recovery next to a failing model | Major | G |

The eight Blockers (F-01, F-02, F-08, F-09, F-11, F-12, F-26, F-27) are what milestone M1 in
[04-task-plan.md](04-task-plan.md) must close first. Without them B does not finish a round with
the model's help.
