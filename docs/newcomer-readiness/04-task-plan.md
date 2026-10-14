# 04 — Task plan: closing every gap, in order

This is the work, broken into tasks a model (or a person) can execute one at a time. It follows the
house format in `tasks/NN-*.md`: goal, deliverables, acceptance. Each task here is self-contained:
it names what to read, which changes (C-) and friction entries (F-) it closes, the files it
touches, the tests to write first, the evidence to attach, and the traps.

- The *why* of each change is in [03-required-changes.md](03-required-changes.md).
- The visual bar is [05-design-improvements.md](05-design-improvements.md) ("05 §n").
- The final proof is [06-verification-protocol.md](06-verification-protocol.md).

## How to execute this plan

1. **Read first, every task:** `CLAUDE.md`, then the sections of `SPEC.md` and `DESIGN.md` the task
   names, then the task's C- entries in 03 in full.
2. **One task per PR**, in the order below; a task starts only when the previous one in its
   milestone is merged and green (CLAUDE.md). Tasks in different milestones are not parallel
   either: M2 builds on M1's files.
3. **Branch** `task/NN-short-name` (names given per task). The PR description quotes the task's
   acceptance list and ticks each item with evidence: a test name, a screenshot, a recording, or a
   log line.
4. **Tests first** for every decision the task adds in `Sources/MachinePromptsMan/Host`. They run on
   Linux: `swift test` must pass on every push. UI code is macOS-only; the `macos` job in
   `.github/workflows/build.yml` compiles it. If you work on Linux, push and read the macOS job
   before claiming a UI change builds.
5. **Strings** go in `UI/Strings.swift`, colours and sizes in `UI/Theme.swift`. A view never calls
   `Store.apply`; it sends an intent to `AppModel` or `SessionController`.
6. **Defaults** the spec does not settle: comment `[default]` and add a row to SPEC §16 in the same
   PR. **Author decisions** (README) must be confirmed before merging the task that depends on them;
   if one is still open, build behind the recommended option and say so at the top of the PR.
7. **Do not touch** the frozen core (CLAUDE.md "Frozen"). If a task seems to need a core change,
   stop, write it in `tasks/OPEN.md`, and build around it.
8. **Done means:** every acceptance box ticked with evidence, `swift test` green on Linux and macOS,
   and the CHANGELOG "Unreleased" section updated in one or two sentences.

## Overview

| Task | Name | Milestone | Closes (C) | Closes (F) | Depends on |
|---|---|---|---|---|---|
| 12 | Launch, presence and menus | M1 | C-01, C-02, C-03, C-26 (name) | F-01–F-04, F-06, F-19, F-20, F-44 | PR #4 |
| 13 | Choosing Doing and Next | M1 | C-07, C-08 | F-26–F-29 | 12 |
| 14 | The local model, ready on first run | M1 | C-15, C-16, C-17 | F-11–F-17, F-50 | 12 |
| 15 | First-run guide and Help | M1 | C-04, C-05, C-27 | F-07–F-10, F-47, F-49 | 13, 14 |
| 16 | Guidance through the cycle | M1 | C-06, C-09, C-10, C-11, C-12, C-24 | F-30–F-34, F-36 | 13 |
| 17 | Plain language | M2 | C-13, C-14, C-20, C-22 | F-21–F-24, F-39, F-40, F-43, F-48 | M1 |
| 18 | Problems and developer mode | M2 | C-18, C-19 | F-41, F-42, F-46 | 17 |
| 19 | Proposals row by row | M2 | C-25 | F-45 | 17 |
| 20 | Sound, quiet hours, permission | M2 | C-21, C-23 | F-35, F-37 | 17 |
| 21 | Visible node actions, easier grid | M2 | C-29, C-28 | F-18, F-25 | 17 |
| 22 | Identity, type and tokens | M3 | C-26 (icon, install note), 05 §2–§5 | F-05 | M2 |
| 23 | Session pane, cards, model card, menu | M3 | 05 §7, §8, §13, §14 | — | 22 |
| 24 | Graph, grid, settings, guide finish | M3 | 05 §6, §9–§12 | — | 22 |
| 25 | Motion, sound, accessibility, checklist | M3 | 05 §15–§19 | — | 23, 24 |
| 26 | Newcomer verification | M4 | everything | all 50 | 25 |
| 27 | Spoken announcements (deferred) | later | C-30 | F-38 | 26 |

**Milestones.**

- **M1:** B can succeed alone. Closes all eight Blockers. After M1, run the protocol in 06 once
  informally; fix anything it surfaces before M2.
- **M2:** B trusts what they see.
- **M3:** the finish that makes it exceptional.
- **M4:** proof.

Task 13 and task 14 can be built in either order after 12; the order above is the recommended one.

---

## Task 12 — Launch, presence and menus

- **Branch:** `task/12-launch-and-menus`
- **Closes:** C-01, C-02, C-03, C-26 (bundle name only). F-01, F-02, F-03, F-04, F-06, F-19, F-20,
  F-44, part of F-29 and F-47.
- **Read:** DESIGN §4, §7, §11; SPEC §6.8 (which events each state allows); `UI/AppModel.swift`,
  `UI/MenuBar.swift`, `UI/MachinePromptsManApp.swift`, `scripts/build-app.sh`.

**Goal.** Opening the app always shows it; every command is in a menu with its shortcut; there is
one Settings window and a visible Quit.

**Deliverables.**
1. `AppDelegate.applicationDidFinishLaunching`: show the main window unless this was a login-item
   launch (C-01 explains the detection and its fallback).
2. One-time notes (C-01 menu-bar caption, C-02 close note), remembered in `HostSettings`
   (`seenMenuBarNote`, `seenCloseNote`, decoded tolerantly like the existing fields).
3. `UI/AppCommands.swift`: the App, Edit, Session, Node, View and Help menus listed in C-03, built
   with SwiftUI `commands`. Session items enabled from a pure `SessionCommands.enabled(state:)` in
   `Host/Presentation.swift` that mirrors SPEC §6.8. Help items may open placeholders until task
   15 (state this in the PR).
4. Replace the SwiftUI `Settings` scene with `CommandGroup(replacing: .appSettings)`.
5. Menu-bar menu: the header line (05 §14 copy may wait for task 23; the line itself is here).
6. `scripts/build-app.sh`: `CFBundleName` and `CFBundleDisplayName` = "Machine Prompts Man".
7. `AppModel.handleKey` keeps only Space, D, N, the arrows, Return and Esc; everything with a
   modifier moves to the menus.

**Tests first.**
- `PresentationTests.testSessionCommandsFollowThePermissionTable`: for every `SessionState` and no
  session, the enabled set equals SPEC §6.8's row.
- `HostSettings` decoding test: an old `host-settings.json` without the new keys decodes with them
  false.

**Acceptance.**
- [ ] Quit, reopen from Finder: the window appears (recording).
- [ ] With Open at Login on, log out and in: the window does not appear, or the PR states the
      fallback was needed and why.
- [ ] First close of the window shows the close note once; the second close does not (recording).
- [ ] Every shortcut in DESIGN §11 and C-03 appears in a menu (screenshot of each menu).
- [ ] Edit → Undo undoes a rename; Edit → Redo redoes it.
- [ ] App menu → Settings… and ⌘, open the same, single window.
- [ ] Finder, app menu and Activity Monitor show "Machine Prompts Man".
- [ ] `swift test` green on Linux and macOS.

**Traps.**
- Single-key shortcuts (D, N, Space) cannot be menu key equivalents without firing in text fields;
  keep them in the key monitor with its `firstResponder is NSText` check.
- `CommandGroup` closures run on the main actor; capture `AppModel` weakly.
- Changing `CFBundleName` does not change the store folder name (`Persistence` uses its own
  constant); do not rename the folder.

---

## Task 13 — Choosing Doing and Next

- **Branch:** `task/13-choosing-slots`
- **Closes:** C-07, C-08. F-26, F-27, F-28, F-29.
- **Read:** SPEC §6.5 (the commit-by-patch note), §6.5.1, §6.7; DESIGN §6, §8; 05 §6; `Engine.applyPatch`;
  `AppModel.pick`, `commitCheck`; `GraphView.click`, `menuItems`; `GridView.StatusCell`;
  `Cards.swift`.

**Goal.** In IDLE and STRATEGY nothing but Commit or Space starts a round, and B can pick both slots
without knowing about dots or ⌥.

**Deliverables.**
1. `Host/Presentation.swift`: `enum SlotIntent { case pick, patch; static func route(_ state: SessionState?) -> SlotIntent }`
   returning `.pick` for `.idle` and `.strategy`, else `.patch`.
2. Graph context menu, Node menu (task 12) and Grid status menu: "Set as Doing" / "Set as Next" (and
   the Grid's Doing and Next entries) go through `SlotIntent.route`. `.pick` calls
   `AppModel.pick(doing:)` / `pick(next:)`; `.patch` applies the status patch as today.
3. Slot chips on hovered or selected pills, and in the Grid's Title cell, in IDLE and STRATEGY
   (05 §6). A chip that the engine would refuse is dimmed with the plain reason (task 17 adds the
   humanised wording; use the raw reason until then).
4. Slot rows in the session pane are pick targets: click enters choose mode (`AppModel.choosingSlot:
   Slot?`), the hint shows at the bottom of the graph, the next node click picks, Esc cancels
   (handled in `handleKey`, like the dependency mode from PR #4).
5. Commit's disabled reason as a caption under the button (C-07 item 4).
6. Key hint inside the primary button (C-08) and a key-capable Time's-up panel: `final class KeyPanel:
   NSPanel { override var canBecomeKey: Bool { true } }`, `makeKey()` on show, Space and Esc via
   `.keyboardShortcut(.space, modifiers: [])` and `.keyboardShortcut(.cancelAction)`.

**Tests first.**
- `PresentationTests.testSlotIntentPicksInIdleAndStrategyOnly`.
- `HostEngineTests.testPickingBothSlotsDoesNotStartTheRound`: in IDLE with `AppModel`-equivalent
  logic exercised through `SlotIntent` (Host has no AppModel; assert that routing `.pick` sends no
  patch, i.e. the store version is unchanged, and that `send(.commit)` afterwards starts round 1).
- `HostEngineTests.testStatusPatchOutsideIdleAndStrategyStillApplies` (WORK: Set as Next patches).

**Acceptance.**
- [ ] In IDLE: menu "Set as Doing" on A, then "Set as Next" on B: no round starts; the slot rows show
      A and B; Space starts round 1 (recording).
- [ ] In STRATEGY with the previous pair still set: menu "Set as Next" on C does not end STRATEGY
      (recording).
- [ ] Chips appear on hover after 400 ms and on selection at once, only in IDLE and STRATEGY
      (screenshots, light and dark).
- [ ] Clicking the "Doing —" row, then a pill, picks it; Esc cancels choose mode.
- [ ] With another app frontmost, Time's up can be answered with Space and Esc; the other app stays
      active (recording).
- [ ] `swift test` green.

**Traps.**
- Picks are cleared at round start (`AppModel.announced`) and at session end; keep that.
- The model's proposals still apply as patches and can commit; that is intended (C-07 constraints),
  and task 19 labels it.
- A key panel steals keyboard focus from the frontmost app's window while shown; that is accepted
  for a 10 s decision, but return key status when the card closes (`orderOut` does this).

---

## Task 14 — The local model, ready on first run

- **Branch:** `task/14-local-model`
- **Closes:** C-15, C-16, C-17. F-11, F-12, F-13, F-14, F-15, F-16, F-17, F-50.
- **Read:** SPEC §8.1, §8.6, §8.7, §9 (all); CLAUDE.md rules 3 and 4; `Host/Model/ModelAdapter.swift`,
  `ModelTurnCoordinator.swift`, `TurnEngine.swift`; `UI/SettingsView.swift` (`ModelSettingsView`),
  `UI/HeldCard.swift`; Ollama's API: `GET /api/tags` returns `{"models":[{"name":"qwen2.5:7b", ...}]}`;
  `POST /api/generate` accepts `"format":"json"` and `"keep_alive":"30m"`; a body with only `model`
  and `keep_alive` loads the model without generating.

**Goal.** On B's Mac the model is found, offered, testable, warm, and its silence or failure is
always explained.

**Deliverables.**
1. `Host/Model/OllamaCatalog.swift`: `enum OllamaStatus: Equatable { case notRunning, running([String]), error(String) }`;
   `static func parse(_ data: Data) -> OllamaStatus`; `static func fetch(endpoint: URL, timeout: TimeInterval = 2) async -> OllamaStatus`
   (connection refused → `.notRunning`).
2. `OllamaAdapter`: `static func requestBody(prompt:model:) -> [String: Any]` including
   `"stream": false`, `"format": "json"`, `"keep_alive": "30m"`; `complete` uses it.
3. `ModelTurnCoordinator.warmUp()` and `static func mayWarmUp(_ state: SessionState?) -> Bool` (true
   for nil and `.idle` only). Called by `AppModel` after `start_session`, after saving Ollama
   settings, and after first-run "Use it" (task 15). Logged as "warm-up" to the system log and the
   monitor; 60 s timeout; result ignored.
4. Settings → Model for Ollama: status line, model picker from the catalog with "Other…", Test
   button. Test sends one fixed message through the coordinator as an ordinary free turn
   (`.message("Reply with one short sentence to confirm you can read this.")`), only when
   `ModelTurnCoordinator.mayRunFreeTurn(state)` is true; otherwise Test is disabled with
   "Available between rounds." Its reply is shown in the Model tab, not in the session pane.
5. `Host/Model/ModelFailure.swift`: `enum ModelFailure: Equatable { case notRunning, modelMissing(String), timedOut, unreadable, other(String) }`
   and `static func classify(_ message: String, model: String) -> ModelFailure` working from the
   coordinator's `failure` string and the turn log's error (URL error codes, "HTTP 404", "model
   ... not found", deadline).
6. `HeldCardView` and `SessionPaneView`: the always-present "Between rounds" area when a model is
   configured, the placeholder lines and disabled Message field during work, the classified
   failure line with "Model settings…" and "Turn off the model" (C-17).
7. SPEC §16 rows: Ollama JSON mode and `keep_alive` 30 m [default]; warm-up at session start [default].

**Tests first.**
- `ModelTurnTests.testOllamaCatalogParsesInstalledModels` (recorded JSON with two models; empty
  list; malformed JSON → `.error`).
- `ModelTurnTests.testOllamaRequestBodyAsksForJSONAndKeepsTheModelLoaded`.
- `ModelTurnTests.testWarmUpIsRefusedInSilentStates`: `mayWarmUp` false for WORK, TIME_UP, SNOOZE,
  STATUS, STRATEGY, BREAK; true for nil and IDLE. Also: calling `warmUp()` in WORK makes no adapter
  call (use the fake adapter's call count).
- `ModelTurnTests.testModelFailureClassification`: one case per enum value from realistic strings.
- `ModelTurnTests.testAJSONOnlyReplyBecomesAFullEnvelope`: a raw `{"say":..,"patch":[..]}` (what
  JSON mode returns) parses with its patch (ladder step 3).

**Acceptance.**
- [ ] On a Mac with Ollama running and one model pulled, Settings → Model lists it; Test answers;
      the time is shown (screenshot).
- [ ] With Ollama quit, the status line says it is not running and how to fix it (screenshot).
- [ ] With a wrong model name, the failure line says the model is not installed (screenshot).
- [ ] Cold Ollama, 7B model, default settings: the first round's phase turn arrives before STATUS
      ends; proposals appear in STRATEGY. Record the measured latency in the PR.
- [ ] During WORK, the pane says when the model will speak; the Message field is disabled
      (screenshot).
- [ ] With an endpoint that never answers (e.g. `nc -l 11999` and the endpoint set to it), a full
      round completes normally and the failure line appears in STRATEGY (CLAUDE.md rule 4).
- [ ] `swift test` green.

**Traps.**
- `URLSession` lives in `FoundationNetworking` on Linux; import it conditionally, as `ModelAdapter.swift` does.
- JSON mode makes Ollama return a bare object, not a fenced block; that is fine (ladder step 3),
  but the prompt template still asks for a fence. Do not change `PromptTemplate` (its version is
  logged); if a change seems needed, bump `PromptTemplate.version` and explain in the PR.
- The warm-up must not count as a turn: it must not touch `current`, `busy` or the turn log.
- Never poll Ollama on a timer during WORK; fetch the catalog only when the Model tab or the
  first-run guide is shown.

---

## Task 15 — First-run guide and Help

- **Branch:** `task/15-first-run-and-help`
- **Closes:** C-04, C-05, C-27. F-07, F-08, F-09, F-10 (with task 16), F-47, F-49.
- **Read:** DESIGN §1, §4, §11 (first-run criterion in tasks/10); 05 §11, §17, §20; `GraphView`
  (goal card), `AppModel.nameGoal`, `addChild`; task 14's `OllamaCatalog`.

**Goal.** A fresh install teaches itself in three quiet steps, and every concept has a page.

**Deliverables.**
1. `UI/FirstRunGuide.swift`: the three steps of C-04, keyboard-first (Return advances, Esc goes back
   a step, ⌘. skips), in the right pane, replacing the goal card. Step 3 appears only if
   `OllamaCatalog.fetch` returned models; "Use it" saves the settings and calls `warmUp()`.
2. `HostSettings.finishedFirstRun`; the guide shows when the store is fresh **or** when the store
   has only the root and the flag is false (covers a person who quit during the guide).
3. Graph empty state: the "Add a step  ⌘N" ghost pill (05 §9).
4. `UI/HelpView.swift` with the six sections of C-05, the cycle diagram as a vector view, and a
   separate Keyboard Shortcuts window. Every number from `SessionConfig` / live settings through
   `Announcement.fmt`. Wire Help menu items (task 12) and the "?" footer button.
5. Settings → General: "Your plan is saved automatically…" with the path and Show in Finder (C-27).

**Tests first.**
- `PresentationTests.testFirstRunShowsForAFreshOrRootOnlyStore`: a pure
  `FirstRun.shouldShow(store:finished:)`.
- `PresentationTests.testHelpNumbersComeFromTheConfig`: a pure `HelpFacts.make(config)` returns the
  snooze length, reminder times, planning window and break; assert equality with `SessionConfig`.

**Acceptance.**
- [ ] Fresh store to "goal plus three steps in the graph" with the keyboard only, under 60 s
      (recording, with a visible clock).
- [ ] With Ollama models present, step 3 offers the first model; "Use it" makes Settings → Model show
      it selected.
- [ ] "Skip" on step 1 leaves a usable app with a root named "Goal".
- [ ] Help opens from the menu and from "?"; every section is present; numbers change when Settings
      change (screenshots before and after changing the round length).
- [ ] No string in the guide or Help uses a spec symbol (R, q, z, x, Ls, Lb, G) or the word "node".
- [ ] `swift test` green.

**Traps.**
- The guide is UI state, not store state, except for the nodes it creates through `AppModel.perform`.
- Rule 8: no welcome banner, no "Let's get started!", no illustrations. Read 05 §20 before writing copy.

---

## Task 16 — Guidance through the cycle

- **Branch:** `task/16-cycle-guidance`
- **Closes:** C-06, C-09, C-10, C-11, C-12, C-24. F-10, F-30, F-31, F-32, F-33, F-34, F-36.
- **Read:** SPEC §6.2, §6.5–§6.7, §6.6.2; DESIGN §6, §7; 05 §7, §8; `SessionPaneDisplay`,
  `Phase`, `Metrics`, `Engine` (`sitCheck`, auto-commit), `Simulator`, `IllustratedSessionTests`.

**Goal.** In every state the pane says what to do now and what will happen next, with numbers that
equal what the engine will do.

**Deliverables (all decisions pure, in `Host/Presentation.swift` or a new `Host/Guidance.swift`).**
1. `PhaseGuide.make(store:now:) -> PhaseGuide` (cases per C-06's table, carrying any values the
   string needs) and its strings.
2. `SnoozePreview.make(store:now:) -> (stopAway: TimeInterval, snoozeAway: TimeInterval?)`; `nil`
   snooze when `z == zMax`.
3. `AutoCommitPreview.make(store:) -> (doing: NodeID?, next: NodeID?)` mirroring SPEC §6.7.
4. `BreakForecast.likely(store:now:) -> Bool` as C-11 defines it.
5. Session pane: guide line, consequence caption under the snooze/stop buttons, the two-step End
   session (C-12), and "Stops in N s" on the Time's-up card (C-24).

**Tests first.**
- `GuidanceTests.testSnoozePreviewEqualsTheStatusLengthTheEngineUses`: drive a session with the
  `Simulator` to TIME_UP with z = 0, 1, 2 and x = 0, 1, 2; preview, then send stop or snooze-then-stop,
  and compare with the session's `statusLength`.
- `GuidanceTests.testAutoCommitPreviewEqualsTheAutoCommit`: several stores (slots set, D vacant, N
  vacant, both vacant, no open nodes); let STRATEGY lapse; compare.
- `GuidanceTests.testBreakForecastIsTrueOnlyInTheRoundBeforeABreak`: replay the illustrated
  session; the forecast is true in exactly the WORK phases followed by BREAK.
- `GuidanceTests.testPhaseGuideCoversEveryState`.

**Acceptance.**
- [ ] Screenshot of the pane in every state (none, IDLE incomplete, IDLE ready, WORK, TIME_UP,
      SNOOZE, STATUS, STRATEGY, BREAK), light and dark.
- [ ] The consequence caption's numbers match the STATUS that follows (recording in test mode).
- [ ] In STRATEGY the auto-commit pair is named and is what happens when it lapses (recording).
- [ ] The break warning appears in the round before a break (recording in test mode).
- [ ] One click on End session does not end it; Esc or 5 s reverts the control.
- [ ] Announcements are unchanged (diff of `Announcement.swift` is empty).
- [ ] `swift test` green.

**Traps.**
- `Metrics.x` counts done-changes in `[round_start, now]`; preview with the same window.
- STATUS ≥ Lb resets seated time; the forecast must apply that rule, or it warns wrongly after a
  long STATUS.

---

## Task 17 — Plain language

- **Branch:** `task/17-plain-language`
- **Closes:** C-13, C-14, C-20, C-22. F-21, F-22, F-23, F-24, F-39, F-40, F-43, F-48.
- **Read:** `MpmCore/Store.swift` (`ValidationError`), `MpmCore/Config.swift` (`ConfigError`),
  `ModelTurnCoordinator.DispositionError`; `AppModel.perform`, `show(toast:)`; `UI/SettingsView.swift`;
  05 §17; the author decision on tasks/05's "verbatim".

**Goal.** No person-facing text contains an id, a raw enum value or a formula symbol, and every
refusal can be read before it disappears.

**Deliverables.**
1. `Host/RefusalExplanation.swift`: `enum RefusalExplanation: Equatable` with one case per error
   case, carrying titles; `static func make(_ error: Error, store: Store) -> RefusalExplanation`.
   Strings render each case (C-13 examples).
2. Toast timing: 2 s + 60 ms per character, max 8 s, held while hovered; the raw error goes to the
   monitor detail (`monitor.emit(.man, ..., detail: "\(error)")`).
3. Blocked-node tooltip "Waiting for …"; the one-time undo note (C-13 item 4).
4. `Strings.statusWord` display names; "Delete" with its tooltip (C-14).
5. Settings labels, captions, the renamed table, the rule sentences with editable thresholds (C-20).
6. "Pause nudges" wording everywhere for the attention snooze (C-22).
7. `scripts/check-strings.sh`: fails if a string literal in `UI/Strings.swift` matches a node-id
   pattern (`n_[0-9A-Z]{4,}`) or contains one of the retired symbol labels ("Base unit q", "z \\ x",
   "Round length (R)"). The spec symbols may still appear as separate caption strings (C-20). Run
   it in both CI jobs (06 §6).

**Tests first.**
- `RefusalExplanationTests.testEveryValidationErrorHasAnExplanation`: iterate one instance of every
  case (add a test helper listing them; the compiler's exhaustive switch in `make` keeps it honest).
- `RefusalExplanationTests.testExplanationsNeverContainNodeIDs`: render through a test copy of the
  strings (or assert the case carries titles, not ids).

**Acceptance.**
- [ ] Trigger five refusals (set Doing on a done node, add a cyclic dependency, edit during a break,
      move the root, commit two identical slots): each toast is plain and readable (screenshots).
- [ ] Settings screenshots, each tab, light and dark: no single-letter label.
- [ ] Search `UI/Strings.swift` for "snooze": only the round extension uses it.
- [ ] `swift test` green.

---

## Task 18 — Problems and developer mode

- **Branch:** `task/18-problems-and-developer-mode`
- **Closes:** C-18, C-19. F-41, F-42, F-46.
- **Read:** DESIGN §12; `Host/Monitor.swift`; `UI/MainView.swift`, `UI/MonitorView.swift`,
  `UI/MenuBar.swift`, `UI/SettingsView.swift`; author decision A-5 (05 §21).

**Deliverables.**
1. `ProblemPolicy.isPersonFacing(_:)` and a person-facing count on `Monitor` (keep the existing
   counts for the developer monitor).
2. The badge shows the newest person-facing problem's plain title and opens its fix.
3. `HostSettings.developerTools` (default false) gating the Monitor segment, System Monitor, Test
   Mode items; `RightPane` restore falls back to `.graph` when the monitor is hidden.
4. Test-mode hairline and header text (C-19).

**Tests first.** `MonitorTests.testOnlyPersonFacingProblemsCountForTheBadge` (a late turn: no; an
abandoned turn: no; two consecutive unreachable failures: yes; a failed disk write: yes).

**Acceptance.**
- [ ] Fresh install: segmented control shows Graph and Grid only (screenshot).
- [ ] Developer tools on: Monitor, System Monitor and Test Mode return (screenshot).
- [ ] With Ollama quit, after two failed turns the badge reads "Model not reachable" and opens
      Settings → Model.
- [ ] `swift test` green.

---

## Task 19 — Proposals row by row

- **Branch:** `task/19-proposal-rows`
- **Closes:** C-25. F-45.
- **Read:** SPEC §5.2–§5.3, §8.5; DESIGN §6; `ModelTurnCoordinator.accept/reject/lock`; `UI/HeldCard.swift`.

**Deliverables.** `reject(_:ops:)` (Declined entry for those ops only, others stay pending); per-row
Accept and Reject; "Never suggest for these" with its in-row explanation; the "Accepting this starts
the next round." caption when accepting would fill both slots in STRATEGY (a pure
`ProposalEffect.startsRound(proposal:ops:store:)`).

**Tests first.**
- `ModelTurnTests.testRejectingOneRowKeepsTheOthersAcceptable`.
- `ModelTurnTests.testStartsRoundIsTrueWhenAcceptingFillsBothSlotsInStrategy`.

**Acceptance.** [ ] per-row Reject works (recording); [ ] the starts-round caption appears only when
true; [ ] `swift test` green.

---

## Task 20 — Sound, quiet hours, permission

- **Branch:** `task/20-sound-and-permission`
- **Closes:** C-21, C-23. F-35, F-37.
- **Read:** DESIGN §10; tasks/10 and tasks/11 (the sentences these change); `AppModel.quietNow`,
  `announced`; author decisions for C-21's default and C-23.

**Deliverables.** The "Sounds quiet until …" indicator (pane footer, menu header); the "Quiet hours
also silence session sounds" setting with the decided default; notification permission requested
at the first Start session with its one-line reason.

**Tests first.** `PresentationTests.testSoundsQuietUntilIsTheQuietHoursEnd` (pure, using
`AttentionPolicy.quietHoursEnd`).

**Acceptance.** [ ] At 22:30 in a session, the indicator shows and sounds follow the setting
(recording with the system clock set, or a test-mode clock); [ ] no permission prompt during a
round; [ ] `swift test` green.

---

## Task 21 — Visible node actions, easier grid

- **Branch:** `task/21-node-actions-and-grid`
- **Closes:** C-29, C-28. F-18, F-25.
- **Read:** DESIGN §8, §9; 05 §9, §12; `UI/GraphView.swift`, `UI/GridView.swift`.

**Deliverables.** The selection action strip (hidden while dragging, panning, in BREAK); the Due
popover with Today / Tomorrow / Next week; the full-height progress hit area with a hover
percentage.

**Acceptance.** [ ] Every action in the strip works and matches the context menu (recording);
[ ] the strip never covers the selected pill and stays on screen at the canvas edges;
[ ] Due and progress edits (recording); [ ] `swift test` green.

---

## Task 22 — Identity, type and tokens

- **Branch:** `task/22-identity-type-tokens`
- **Closes:** C-26 (icon and install note), 05 §2, §3, §4, §5; amendments A-1, A-2, A-3. F-05.
- **Read:** 05 §2–§5, §21; DESIGN §2–§4; `UI/Theme.swift`, `UI/MenuBar.swift`, `scripts/build-app.sh`, `README.md`.

**Deliverables.** App icon set and build-script copy; README Gatekeeper note; tracking and caps
label fonts in `Theme`; new tokens with their contrast table; menu-bar glyph per A-1 as a template
image; title-bar alignment of the segmented control; DESIGN.md edits for the approved amendments.

**Acceptance.** [ ] Icon at 16, 32, 128, 512 px (screenshots of Finder and Dock); [ ] contrast table
in the PR, every text token ≥ its target; [ ] menu-bar glyph in light and dark menu bars, with
Reduce Transparency on (screenshots); [ ] DESIGN.md updated for each approved amendment.

---

## Task 23 — Session pane, cards, model card, menu

- **Branch:** `task/23-session-pane-finish`
- **Closes:** 05 §7, §8, §13, §14; amendment A-4, A-6.
- **Read:** 05 §7, §8, §13, §14, §15; DESIGN §5–§7.

**Deliverables.** Ring reminder ticks, snooze budget dots, "what the time counts" caption, the
vertical rhythm of 05 §5 and §7, the footer; Time's-up settle animation and caption layout; break
band notch handling; close-note and toast styling; the "Between rounds" card typography, question
bar, proposal row layout and accept/reject motion, and the deadline hairline instead of a spinner;
the menu-bar menu header and grouping.

**Acceptance.** [ ] Screenshots of every pane state at 980 × 640 and 760 × 480, light and dark;
[ ] recordings of the card, the ring through a reminder, and accepting and rejecting a proposal,
each with Reduce Motion off and on; [ ] the 05 §19 items 1, 2, 3, 8, 13, 14 ticked with evidence.

---

## Task 24 — Graph, grid, settings, guide finish

- **Branch:** `task/24-graph-grid-settings-finish`
- **Closes:** 05 §6 (finish), §9, §10, §11, §12; amendment A-7.
- **Read:** 05 §6, §9–§12; DESIGN §8, §9.

**Deliverables.** Pill hover and focus states, LOD at zoom thresholds, faded finished edges, drop
preview, double-click and ⌘0 fit, ⌘+/⌘− zoom; Grid row height, depth guides, status dots,
selection token, quick-log placeholder; Settings toolbar tabs, the round timeline preview, inline
validation, Model tab layout; guide card motion and step-2 pill previews; Help typography and key
caps.

**Acceptance.** [ ] Graph at 300 nodes pans at 60 fps on an M1 (tasks/10; Instruments screenshot);
[ ] screenshots of the graph at 30%, 100% and 250% zoom; [ ] the Settings timeline updates live
(recording); [ ] 05 §19 items 4, 5, 6, 7, 9, 10, 11 ticked.

---

## Task 25 — Motion, sound, accessibility, checklist

- **Branch:** `task/25-motion-sound-a11y`
- **Closes:** 05 §15–§19; amendments A-8, A-9.
- **Read:** 05 §15–§19; DESIGN §5, §10, §11; tasks/10 accessibility deliverables.

**Deliverables.** The motion table of 05 §15 implemented and audited; the sound levels and fades;
VoiceOver labels and graph accessibility actions; Increase Contrast mapping; the full 05 §19
checklist with evidence; DESIGN.md §11 appended with the checklist (A-9).

**Acceptance.** [ ] Every row of 05 §15 recorded with Reduce Motion off and on; [ ] a VoiceOver
recording completing one round with no mouse; [ ] measured loudness of each sound (any LUFS meter;
numbers in the PR); [ ] all 14 checklist items ticked.

---

## Task 26 — Newcomer verification

- **Branch:** `task/26-newcomer-verification`
- **Closes:** proves every C- and F- entry.
- **Read:** [06-verification-protocol.md](06-verification-protocol.md), all of it.

**Deliverables.** Run the protocol with at least two people who have never seen the app (or, if
none are available, with a model operating the app through accessibility automation, and say so).
Record the results table from 06. For every task step that fails its criterion, open a fix PR
before closing this task. Update [02-friction-inventory.md](02-friction-inventory.md): mark each
F-entry "Closed by task NN (PR #…)" or "Open: …".

**Acceptance.** [ ] Every protocol step passes for every participant; [ ] the results table and
recordings are attached; [ ] 02 shows no open Blocker or Major entry.

---

## Task 27 — Spoken announcements (deferred)

- **Branch:** `task/27-voice`
- **Closes:** C-30. F-38.
- **Read:** SPEC §10; CLAUDE.md's note on the reference app's TTS; DESIGN §10.

**Deliverables.** An optional voice for announcements and `say`/`ask`, off by default, a setting to
choose the voice, never speaking patches or diffs (SPEC §10), muted by Mute Sounds and by quiet hours
under the same rule as task 20.
