# 03 — Required changes: what has to be different, and why

This document says **what** must change for user B (see [02-friction-inventory.md](02-friction-inventory.md))
to succeed alone, and **why** each change is the right one. It does not say how to sequence the
work; [04-task-plan.md](04-task-plan.md) does. The visual quality bar for every change is in
[05-design-improvements.md](05-design-improvements.md).

Each change has:

- **Closes** — the friction entries (F-numbers) it resolves. Every F-number is closed by at least
  one change; the traceability table at the end proves it.
- **Change** — the behaviour after the change, stated so it can be checked.
- **Where** — the files that change. `Host/` is `Sources/MachinePromptsMan/Host`, `UI/` is
  `Sources/MachinePromptsMan/UI`.
- **Constraints** — the rules from CLAUDE.md, SPEC.md or DESIGN.md that limit the change.
- **Done when** — the observable result.
- **Author decision** — present only when the change departs from something an existing task,
  SPEC section or DESIGN section asked for. All are **resolved in [07-decisions.md](07-decisions.md)**;
  where 07 turned a decision into a setting, build the setting with the default it gives.

## Rules every change obeys

1. **The core is frozen.** `Config.swift` formulas, the `Engine.swift` transition table,
   `Envelope.swift`'s four keys, SPEC §13 invariants and the existing tests in `Tests/MpmCoreTests`
   do not change. Nothing below needs them to. New pure helpers may be added to MpmCore or Host.
2. **Announcements keep their wording** (CLAUDE.md rule 6). Every explanation added below is a new
   UI string in `UI/Strings.swift`, shown *beside* the announcement, never instead of it.
3. **The model stays silent during work** (CLAUDE.md rule 3). No change starts a model request in
   WORK, TIME_UP, SNOOZE or BREAK. The warm-up in C-16 is the only new request, and it is limited
   to IDLE, no session, and the Settings test.
4. **No cheese** (CLAUDE.md rule 8). Guidance is short, plain, and goes away when it is no longer
   needed. No mascots, no celebrations, no exclamation marks, no emoji, no "Great job".
5. **Strings live in one place** (DESIGN §11), colors and sizes in `Theme.swift` (DESIGN §3–4).
6. **Logic that can be tested is tested.** Anything that decides (what to show, what to route
   where, what counts as a problem) is a pure function in `Host/` with a test in
   `Tests/MachinePromptsManTests`, so it runs on Linux. Views only lay it out.
7. **Every default the spec does not settle** is marked `[default]` in a comment and gets a row in
   SPEC §16 "Defaults chosen" in the same PR (CLAUDE.md).

---

## Getting in and staying oriented

### C-01 — Show the window when the person opens the app
- **Closes:** F-01, F-02.
- **Change:** a launch the person started (Finder, Spotlight, Dock, `open`) shows the main window.
  A launch by the login item (`SMAppService`) does not. The idle menu-bar glyph stays (DESIGN §4),
  but the first time the app runs, the window also says, once, where the app lives: a one-line
  caption under the session pane, "Machine Prompts Man stays in the menu bar while it runs.",
  removed after the first session starts.
- **Where:** `UI/MachinePromptsManApp.swift` (`AppDelegate.applicationDidFinishLaunching`),
  `UI/AppModel.swift` (`start(fresh:)`), `Host/HostSettings.swift` (a `seenMenuBarNote` flag),
  `UI/Strings.swift`.
- **How to tell a login launch:** at launch, `NSAppleEventManager.shared().currentAppleEvent` is a
  `kAEOpenApplication` event whose `keyAEPropData` parameter is `keyAELaunchedAsLogInItem` for
  login-item launches. Verify this on macOS 14 and 15 with `SMAppService`; if it is not reliable,
  show the window on every launch (a visible window at login is acceptable; an invisible app on a
  deliberate open is not). Treat "unknown" as user-initiated.
- **Constraints:** none.
- **Done when:** quitting and reopening from Finder shows the window every time; enabling Open at
  Login and logging in does not.

### C-02 — Make the menu-bar item self-explanatory
- **Closes:** F-03, F-04.
- **Change:** a left click still opens the window (fast path, DESIGN §4). The right-click menu
  gains a disabled header line with the state and time ("Work · 6:12 left", or "No session") and
  is also reachable from the window's main menu (C-03). The first time the person closes the main
  window, a borderless, non-activating note is anchored under the menu-bar item for 4 s:
  "Still running. Click here to open the window." Never shown again.
- **Where:** `UI/MenuBar.swift`, `UI/AppModel.swift` (`MainWindowDelegate`), `Host/HostSettings.swift`
  (`seenCloseNote`), `UI/Strings.swift`.
- **Constraints:** DESIGN §7 forbids cards that fade out on their own except as listed; this note
  is a new listed exception (author decision below).
- **Done when:** a person who closes the window sees where the app went, once.
- **Author decision:** add the close note to DESIGN §7's list of self-dismissing surfaces. **Resolved: adopted (07 D-5).**

### C-03 — A real main menu with every command and its shortcut
- **Closes:** F-04, F-19, F-20, F-29 (partly), F-44, F-47 (partly).
- **Change:** while the window is open the app shows a complete main menu built with SwiftUI
  `commands`:
  - **App:** About, Settings… ⌘, (the one Settings window), Quit ⌘Q.
  - **Edit:** Undo ⌘Z and Redo ⇧⌘Z wired to `SessionController.undo/redo`, enabled from
    `canUndo/canRedo`, titled "Undo Rename" style when possible.
  - **Session:** Start Session, Finish, Snooze, Stop, Commit, End Session…, each enabled only in
    the states SPEC §6.8 allows, with Space shown as the shortcut on whichever is primary now;
    Schedule…; Session Transcript.
  - **Node:** New Node ⌘N, Rename ↩, Set as Doing D, Set as Next N, Mark Done, Cross Out ⌘⌫,
    Add Dependency…, Lock.
  - **View:** Graph ⌘1, Grid ⌘2 (Monitor ⌘3 only in developer mode, C-19), Fit ⌘0.
  - **Help:** "How Machine Prompts Man Works" (C-05), "Keyboard Shortcuts" (C-05).
  The SwiftUI `Settings` scene is replaced by `CommandGroup(replacing: .appSettings)` that calls
  `AppModel.showSettings()`, so there is exactly one Settings window.
- **Where:** `UI/MachinePromptsManApp.swift` (new `AppCommands.swift` beside it), `UI/AppModel.swift`
  (the key monitor keeps only the single-key shortcuts that menus cannot carry: Space, D, N, arrows,
  Return, Esc).
- **Constraints:** single-letter shortcuts (D, N) must not fire while a text field has focus; keep
  that check in `handleKey`.
- **Done when:** every keyboard action in the app is visible in a menu with its key; Edit → Undo
  undoes the last plan change; there is one Settings window.

### C-26 — One name, an icon, and an honest install note
- **Closes:** F-05, F-06.
- **Change:** `CFBundleName` and `CFBundleDisplayName` are "Machine Prompts Man"; the executable
  name may stay. The app gets an icon (see 05 §2). README "Install" explains Gatekeeper's "Open
  Anyway" in System Settings → Privacy & Security for an un-notarized build, in two sentences.
- **Where:** `scripts/build-app.sh`, `README.md`, a new `Resources/AppIcon.icns` copied by the
  build script.
- **Done when:** Finder, the app menu, Activity Monitor and notifications all say "Machine Prompts
  Man".

---

## Understanding the system

### C-04 — A quiet first-run guide inside the window
- **Closes:** F-07, F-08, F-09, F-26 (partly).
- **Change:** on a fresh store the right pane shows a three-step guide in place of the empty
  graph. Each step is one card in the graph area (DESIGN §4 card style: 10 pt radius, 1 px line,
  no shadow), one at a time, with a small "1 of 3" counter:
  1. **Goal.** "What are you working toward? This is the top of your plan." Field, Return to
     continue. (Replaces today's goal card; same `nameGoal` intent.)
  2. **Steps.** "Add the first few things to do. Return adds each one." A field that adds children
     of the goal on Return and lists them below as they are added; "Continue" once there is at
     least one, and the hint "You can add more any time with ⌘N."
  3. **Model** (only if C-15 found Ollama with models): "A local model is ready on this Mac:
     qwen2.5:7b. It can suggest changes between rounds, never during them." Buttons "Use it" and
     "Not now". Skipped if nothing was found.
  Then the graph appears with the new nodes, and the session pane shows the IDLE guidance from
  C-06. A "Skip" link on every step goes straight to the graph. The guide never returns once
  finished or skipped (`HostSettings.finishedFirstRun`); Help → How It Works covers the rest.
- **Where:** new `UI/FirstRunGuide.swift`; `UI/GraphView.swift` (remove the goal card);
  `UI/AppModel.swift`; `Host/HostSettings.swift`; `UI/Strings.swift`.
- **Constraints:** no carousel, no illustrations of people, no progress confetti. All edits go
  through `AppModel.perform` (CLAUDE.md: views never call `Store.apply`).
- **Done when:** a fresh store reaches "graph with goal and three steps" from the keyboard alone in
  under a minute (tasks/10's first-run criterion, kept).

### C-05 — "How it works", in the app
- **Closes:** F-09, F-10, F-19, F-31 (partly), F-43, F-47, F-49.
- **Change:** a Help window (one scrolling page, 560 pt wide), opened from Help in the main menu,
  from a small "?" button at the bottom of the session pane, and from the first-run guide. Sections:
  1. **The cycle**: a static diagram of Work → Time's up → Snooze → Away → Plan next → (Movement
     break) → Work, with one sentence each, using the default times and the real formula in words
     ("Each snooze doubles the away time; each thing you finish divides it.").
  2. **Doing and Next**: what they are, how to choose them (click the dot, ⌥-click, D and N, or the
     Doing/Next buttons from C-07).
  3. **The model**: when it speaks (between rounds and when no session runs), what proposals are,
     Accept, Reject and "Never suggest", and that it never changes anything by itself.
  4. **Nudges and the schedule**: what the five rules mean, quiet hours, the daily limit.
  5. **Keyboard shortcuts**: the full table (also its own small window, Help → Keyboard Shortcuts).
  6. **Your data**: saved automatically after every change, where, and that closing the window or
     quitting loses nothing.
- **Where:** new `UI/HelpView.swift`; `UI/AppModel.swift` (`showHelp`); `UI/Strings.swift` (all the
  text, as named constants).
- **Constraints:** the help text must match the engine. Any number in it comes from
  `SessionConfig.default` or the live settings (`Announcement.fmt`), never typed by hand.
- **Done when:** every concept on the main screen has a sentence in Help, and every number in Help
  matches Settings.

### C-06 — A plain line under the state name
- **Closes:** F-10, F-30, F-32 (partly), F-33 (partly).
- **Change:** beneath the header ("WORK  Round 2  Seated 18 min") the session pane shows one line
  of guidance, 13 pt `ink2`, chosen by a pure function `PhaseGuide.for(state:session:store:now:)`:

  | State | Line |
  |---|---|
  | none | "Start a session to work in timed rounds." |
  | IDLE, slots incomplete | "Choose what you are doing and what comes next, then start the round." |
  | IDLE, slots ready | "Ready. Press Space to start the round." |
  | WORK / SNOOZE | "Work on Doing. Press Space when it is done." |
  | TIME_UP | "Snooze for more time, or stop and step away." |
  | STATUS | "Step away from the desk. If anything changed, mark it now. Planning starts at 0:00." |
  | STRATEGY | "Choose what comes next. If you do not, Doing and Next stay as they are." |
  | BREAK | "Stand up and move. The next round starts after the break." |

  The capitalised state names stay as the header (they are the engine's states); the line
  explains them.
- **Where:** `Host/Presentation.swift` (a `PhaseGuide` enum of cases, no text), `UI/Strings.swift`
  (the text per case), `UI/SessionPane.swift`.
- **Constraints:** announcements unchanged; the line never contains a number the engine did not
  produce.
- **Done when:** in every state the pane says, in plain words, what B should do now.

### C-14 — Display names for statuses and plain menu labels
- **Closes:** F-22, F-23.
- **Change:** `Strings.statusWord` returns "Open", "Doing", "Next", "Done", "Crossed out",
  "Blocked". "Delete Typo" becomes "Delete" with the tooltip "Only for a step that was never worked
  on. Others can be crossed out, which keeps their history."
- **Where:** `UI/Strings.swift`, `UI/GraphView.swift`.
- **Done when:** no raw enum value appears on screen.

---

## Choosing Doing and Next

### C-07 — One way to choose the slots, visible, and never an accidental commit
- **Closes:** F-26, F-27, F-28.
- **Change:**
  1. **Menus route to picks, not patches, in IDLE and STRATEGY.** "Set as Doing" and "Set as Next"
     (graph context menu, Node menu, Grid status menu choosing Doing or Next) call
     `AppModel.pick(doing:)` / `pick(next:)` when the state is IDLE or STRATEGY. In every other
     state, and with no session, they keep applying the status patch as today. The decision is a
     pure function `SlotIntent.route(state:) -> .pick | .patch` in `Host/Presentation.swift`.
  2. **Visible pick buttons.** In IDLE and STRATEGY, hovering a pill (or selecting it) shows two
     small text chips to its right, "Doing" and "Next", in the slot colors (05 §6). The dot and ⌥
     click stay as fast paths. The Grid gets the same two chips in the Title cell on hover.
  3. **The slot rows are targets too.** Clicking the "Doing —" row in the session pane enters
     choose-Doing mode: the hint "Click a step to make it Doing. Esc cancels." appears at the bottom
     of the graph (same mechanism as choosing a dependency), and the next click picks.
  4. **The reason is on screen, not in a tooltip.** When Commit is disabled the reason appears as a
     caption under the button: "Choose Doing and Next." or the engine refusal humanised by C-13.
- **Where:** `Host/Presentation.swift`, `UI/AppModel.swift`, `UI/GraphView.swift`, `UI/GridView.swift`,
  `UI/SessionPane.swift`, `UI/Strings.swift`.
- **Constraints:** the engine's commit-by-patch rule (SPEC §6.5 note) is frozen and still applies
  to patches; the change only stops the *menus* from sending a patch in those two states. Model
  proposals that set both slots are unaffected and still commit when accepted, which is the
  SPEC's intent; the proposal row must then say "Accepting this starts the round." (C-25).
- **Done when:** in IDLE and STRATEGY, nothing B does with a menu starts a round; only Commit or
  Space does. B can pick both slots without knowing about dots or ⌥.

### C-08 — Space shown, and keys that work on the Time's-up card
- **Closes:** F-29.
- **Change:** the primary button in the session pane shows its key as a trailing, `ink2`, 11 pt
  glyph ("Finish  ␣"). The Time's-up panel becomes key when it appears (an `NSPanel` subclass with
  `canBecomeKey = true`, still `.nonactivatingPanel`, so the frontmost app is not activated); in
  it, Space snoozes and Esc stops, through `.keyboardShortcut` on its two buttons.
- **Where:** `UI/SessionPane.swift`, `UI/Cards.swift`.
- **Constraints:** the card must not steal activation from the app B is working in.
- **Done when:** with another app frontmost, Time's up can be answered from the keyboard.

---

## Living through the cycle

### C-09 — Show what a snooze costs before it is chosen
- **Closes:** F-31.
- **Change:** under the Snooze and Stop buttons (session pane and Time's-up card), one caption
  line: "Stop now: away 2:30. Snooze: away 5:00." computed by a pure
  `SnoozePreview.make(store:session:now:)` using `SessionConfig.statusLength(z:x:)` and
  `Metrics.x(in:from:to:)` (both existing pure functions, unchanged).
- **Where:** `Host/Presentation.swift`, `UI/SessionPane.swift`, `UI/Cards.swift`, `UI/Strings.swift`.
- **Done when:** the two numbers equal the STATUS length the engine then uses (test asserts this
  against `Engine.handle`).

### C-10 — Say what happens if planning runs out
- **Closes:** F-32.
- **Change:** in STRATEGY the guide line (C-06) names the pair that auto-commit will keep: "If you
  do not choose, Write copy stays Doing and Fix login stays Next." The pair comes from a pure
  `AutoCommitPreview` that mirrors SPEC §6.7 and is tested against the engine's actual
  auto-commit.
- **Where:** `Host/Presentation.swift`, `UI/SessionPane.swift`, `UI/Strings.swift`.
- **Done when:** the preview equals the auto-commit result in every test case.

### C-11 — Warn before a movement break, and explain the lock
- **Closes:** F-33.
- **Change:** during WORK and SNOOZE, a pure `BreakForecast.likely(session:store:now:)` predicts the
  SIT_CHECK that follows this round (SPEC §6.6.2): if the expected STATUS (stopping now, from
  `SnoozePreview`) is shorter than Lb, and `seated + remaining + expected STATUS + strategy + R > Ls`,
  the guide line ends with "A movement break follows this round." (A STATUS at least Lb long resets
  the sitting clock, so no break follows it.) The
  break-time refusal (C-13) reads "The plan is locked during the movement break. It opens again in
  2:40."
- **Where:** `Host/Presentation.swift`, `UI/SessionPane.swift`, `UI/Strings.swift`.
- **Done when:** the warning appears in the round before every break in the simulator's
  reference session (`IllustratedSessionTests` transcript).

### C-12 — Confirm before ending a session
- **Closes:** F-34.
- **Change:** "End session" becomes a two-step control: the first click turns it into "End this
  session?  End  ·  Keep going" in place for 5 s; the second click on "End" ends it. The main-menu
  item "End Session…" shows a standard sheet. With no round started (IDLE), it ends at once.
- **Where:** `UI/SessionPane.swift`, `UI/AppCommands.swift`, `UI/MenuBar.swift`, `UI/Strings.swift`.
- **Done when:** a single stray click never ends a session.

### C-24 — Say how long the grace window has left
- **Closes:** F-36.
- **Change:** the Time's-up card shows "Stops in 7 s" (tabular digits, `ink2`) above the buttons,
  driven by the same timeline as the grace bar.
- **Where:** `UI/Cards.swift`, `UI/Strings.swift`.

### C-21 — Make quiet hours visible, and let a chosen session be heard
- **Closes:** F-37.
- **Change:** while quiet hours are muting sounds, the session pane footer and the menu-bar menu
  header say "Sounds quiet until 08:00". A new setting in Settings → Attention, "Quiet hours also
  silence session sounds", decides whether sounds play in a session B started during quiet hours.
- **Author decision:** the default of that setting. **Resolved: setting `quietHoursSilenceSessions`, default off (07 D-2).**
- **Where:** `UI/AppModel.swift` (`quietNow`), `Host/HostSettings.swift`, `UI/SettingsView.swift`,
  `UI/SessionPane.swift`, `UI/MenuBar.swift`, `UI/Strings.swift`.

### C-23 — Ask for notifications before the first round, not during it
- **Closes:** F-35.
- **Change:** the permission is requested when B first presses Start session, with the one-line
  reason shown in the pane ("Reminders reach you as notifications when the window is hidden.").
- **Author decision:** tasks/11 asked for the request "at the first reminder"; this moves it to the
  first session start. **Resolved: adopted (07 D-3).**
- **Where:** `UI/AppModel.swift`.

---

## The local model

### C-15 — Find Ollama, list its models, test the connection
- **Closes:** F-11, F-12, F-13, F-47 (partly).
- **Change:**
  1. **Detection.** At first run and whenever the Model tab opens, the host calls
     `GET {endpoint}/api/tags` with a 2 s timeout. The result is a pure value
     `OllamaStatus = .notRunning | .running(models: [String]) | .error(String)` parsed by
     `OllamaCatalog.parse(_:)` (Host, tested with recorded JSON).
  2. **First run.** If models are found, the first-run guide offers the first one (C-04 step 3).
     "Use it" saves `ModelSettings(kind: .ollama, ollamaModel: name)` through
     `AppModel.applyModelSettings`.
  3. **Settings → Model.** For Ollama: a status line ("Ollama is running. 2 models installed." /
     "Ollama is not running. Open the Ollama app, then check again."), a model **picker** filled
     from the catalog with "Other…" for a typed name, and a **Test** button. Test sends one short
     prompt through the real adapter and turn engine (outside any session, so allowed), and shows
     "Answered in 4.2 s. Reply understood." / "Answered, but the reply could not be read; it will
     be shown as plain text." / the failure in plain words (C-17).
  4. **Default.** `ModelSettings.kind` stays `.none` in code (SPEC §9.4: no model is a valid
     configuration); detection is what turns it on, with B's consent.
- **Where:** new `Host/Model/OllamaCatalog.swift`; `UI/SettingsView.swift`; `UI/FirstRunGuide.swift`;
  `UI/AppModel.swift`; `UI/Strings.swift`.
- **Constraints:** detection is a plain HTTP GET to a local server, not a model turn; it is allowed
  in any state but must not be repeated on a timer during WORK (no polling).
- **Done when:** on B's Mac, the model is offered on first run, and Settings shows the installed
  models and a working Test.

### C-16 — Make a local model fast enough and structured enough
- **Closes:** F-15, F-16.
- **Change:**
  1. `OllamaAdapter` sends `"keep_alive": "30m"` with every request so the model stays loaded
     between rounds, and `"format": "json"` so the reply is a JSON object; the envelope ladder's
     step 3 (SPEC §9.3) reads it. The request body is built by a static
     `OllamaAdapter.requestBody(...)` tested like `AnthropicAdapter.requestBody`.
  2. **Warm-up.** `ModelTurnCoordinator.warmUp()` sends Ollama's load request (`/api/generate` with
     the model and `keep_alive`, no prompt) at `start_session` (state IDLE), after Settings → Save
     and after first-run "Use it". It is not a turn: it is logged to the system log and the
     monitor as "warm-up", has a 60 s timeout, and its result is ignored. A pure
     `ModelTurnCoordinator.mayWarmUp(state)` returns true only for no session and IDLE.
- **Where:** `Host/Model/ModelAdapter.swift`, `Host/Model/ModelTurnCoordinator.swift`,
  `UI/AppModel.swift`.
- **Constraints:** CLAUDE.md rule 3 forbids model calls in WORK, TIME_UP, SNOOZE and BREAK; the
  warm-up is limited to IDLE and no session and tested for it. JSON mode, keep-alive and warm-up
  are settings with defaults on, 30 min and on (07 D-8); SPEC §16 gets a row for each **[default]**.
- **Done when:** with a cold Ollama, the first round's phase turn arrives before STATUS ends on an
  M1 with a 7B model (measure and record in the PR), and proposals appear in STRATEGY.

### C-17 — The model's place, and its failures, in plain words
- **Closes:** F-14, F-17, F-50.
- **Change:**
  1. When a model is configured, the "Between rounds" area is always present in the session pane.
     During WORK, TIME_UP, SNOOZE, STATUS and BREAK it shows one `ink2` line: "The model will
     speak when this round is over." (STATUS adds "Thinking about this round." while the phase
     turn runs.) The Message field is visible but disabled during work, with placeholder "Messages
     open between rounds."
  2. Failures are classified by a pure `ModelFailure.classify(_ error:)` into `notRunning`,
     `modelMissing(name)`, `timedOut`, `unreadable`, `other(String)`, each with its own string:
     "Ollama is not running." / "The model qwen2.5:7b is not installed in Ollama." / "The model
     took too long this round." / "The model's reply could not be read." The line has two actions:
     "Model settings…" and "Turn off the model".
- **Where:** `Host/Model/ModelFailure.swift` (new), `UI/HeldCard.swift`, `UI/SessionPane.swift`,
  `UI/Strings.swift`.
- **Constraints:** nothing from the model is shown during work (rule 3); the placeholder text is
  app copy, not model output.
- **Done when:** B can tell, in every state, whether the model is on, when it will speak, and what
  to do when it fails.

### C-18 — Problems the person can act on, separate from the developer monitor
- **Closes:** F-42.
- **Change:** the badge beside the pane switch counts only *person-facing* problems, decided by a
  pure `ProblemPolicy.isPersonFacing(_ event: MonitorEvent)`: model unreachable or missing twice in
  a row, a failed disk write, a store that could not be saved. A late or abandoned turn alone is
  not one. The badge reads the problem ("Model not reachable", "Could not save") and opens the
  place to fix it (Model settings, or a sheet with "Show Files"). The full monitor keeps every
  event and its own counts, in developer mode (C-19).
- **Where:** `Host/Monitor.swift` (or new `Host/ProblemPolicy.swift`), `UI/MainView.swift`,
  `UI/Strings.swift`.
- **Author decision:** DESIGN §12 defines the badge as "N problems" opening the monitor. **Resolved: with developer tools off the badge is person-facing; with them on it is today's badge (07 D-4).**

### C-25 — Proposals B can read and answer row by row
- **Closes:** F-45.
- **Change:** each row has Accept and Reject (DESIGN §6). `ModelTurnCoordinator.reject(_:ops:)`
  writes a `Declined` entry for those ops only and keeps the rest pending; whole-proposal Reject
  stays. "Lock" becomes "Never suggest for these", with the explanation in the row, not a tooltip:
  "Rejects this and stops suggestions for Fix login and Write copy." A proposal that would fill
  both slots in STRATEGY says "Accepting this starts the next round." on its Accept button's
  caption.
- **Where:** `Host/Model/ModelTurnCoordinator.swift`, `UI/HeldCard.swift`, `UI/Strings.swift`.
- **Done when:** a test rejects one op of a three-op proposal and the other two stay acceptable.

---

## Clarity and trust

### C-13 — Refusals in plain words, with titles, long enough to read
- **Closes:** F-21, F-24, F-48.
- **Change:**
  1. A pure `RefusalExplanation.make(_ error: Error, store:)` maps every `ValidationError`,
     `DispositionError` and `ConfigError` case to a case with node **titles** instead of ids; the
     UI renders each case from `Strings`. Examples: "Fix login is done, so it cannot be Doing.",
     "Record demo is waiting for Fix login, so it cannot be Doing yet.", "The plan is locked during
     the movement break."
  2. A toast stays 2 s plus 60 ms per character, at most 8 s, and stays while the pointer is over
     it. The engine's raw reason goes to the monitor event detail, unchanged.
  3. Hovering a blocked node lists what it waits for: "Waiting for Fix login."
  4. When a commit clears undo history, ⌘Z shows "Undo starts again after a round begins." once
     per session.
- **Where:** `Host/RefusalExplanation.swift` (new), `UI/AppModel.swift` (`perform`, `show(toast:)`),
  `UI/GraphView.swift` (tooltip), `UI/Strings.swift`.
- **Author decision:** tasks/05 asked for "the engine's reason, verbatim". The engine's text is
  kept, verbatim, in the monitor; the person sees the explanation. **Resolved: setting `showEngineWording`, default off (07 D-1).**
- **Done when:** a test covers every `ValidationError` case and no person-facing string contains a
  node id.

### C-20 — Settings in plain language, with the formulas as captions
- **Closes:** F-39, F-40.
- **Change:**
  - Labels: "Round length", "Reminders per round", "Sit for at most", "Movement break", "Time to
    answer Time's up". The spec symbol moves to a trailing `ink2` caption (R, r, Ls, Lb, G) for
    people who know it.
  - "Derived" becomes "What a round looks like": a one-line timeline of the round with reminder
    ticks (05 §10), then "Snooze length 1:15. Up to 3 snoozes. Planning window 1:15."
  - The status table is titled "Away time after a round", rows "No snoozes", "1 snooze"…, columns
    "Nothing finished", "1 finished"…
  - Each nudge rule shows a sentence and its threshold, editable where the core `Settings` already
    has the field: "Overdue: a step whose due date has passed.", "Due soon: due within [3] days.",
    "Stale: Doing or Next untouched for [7] days.", "Unblocked: everything a step was waiting for is
    done.", "Drift: no progress on Doing for [5] days."
- **Where:** `UI/SettingsView.swift`, `UI/Strings.swift`. `dueSoonDays`, `staleDays`, `driftDays` are
  saved with `SessionController.updateSettings` (no core change).
- **Done when:** no setting label is a single letter.

### C-22 — One word for one meaning
- **Closes:** F-43.
- **Change:** "Snooze" means only the round extension. The attention snooze becomes "Pause nudges"
  (Settings section, Schedule window, `Strings.snoozeSystem`, `snoozeHour` …), and the node item
  becomes "Pause Nudges for This Until Tomorrow" / "Resume Nudges for This".
- **Where:** `UI/Strings.swift`.

### C-19 — Developer mode
- **Closes:** F-41, F-46.
- **Change:** Settings → General gets "Show developer tools" (off by default). Off: no Monitor
  segment, no System Monitor menu item, no Test Mode in menus or General settings. On: everything
  as today, and the badge (C-18) also links to the monitor. Test mode's badge becomes a full-width
  1 px `blocked` hairline under the title bar plus "Test 60×" in the header, so it cannot be
  missed.
- **Where:** `Host/HostSettings.swift` (`developerTools`), `UI/MainView.swift`, `UI/MenuBar.swift`,
  `UI/SettingsView.swift`, `UI/AppModel.swift` (`showMonitor`, `RightPane` restore).
- **Author decision:** DESIGN §12 places the Monitor as a third segment for everyone. **Resolved: setting `developerTools`, default off (07 D-4).**
- **Done when:** a fresh install shows only Graph and Grid.

### C-27 — Say that the plan is saved
- **Closes:** F-49.
- **Change:** Help has the "Your data" section (C-05); Settings → General shows "Your plan is saved
  automatically after every change." with the folder path and "Show in Finder".
- **Where:** `UI/SettingsView.swift`, `UI/HelpView.swift`, `UI/Strings.swift`.

### C-28 — Easier Grid cells
- **Closes:** F-25.
- **Change:** clicking an empty Due opens a small popover with Today, Tomorrow, Next week and a
  calendar, instead of setting today at once. The progress cell's hit area is the full row height
  and shows the percentage in `ink2` on hover.
- **Where:** `UI/GridView.swift`.

### C-29 — Visible actions for the selected node
- **Closes:** F-18.
- **Change:** when a node is selected in the graph, a compact action strip appears 8 pt below its
  pill: Rename, Add Step, Mark Done, Cross Out (or Restore), and "More…" which opens the existing
  context menu. It hides while dragging, panning or during BREAK, and fades in with
  `Theme.Motion.fade`.
- **Where:** `UI/GraphView.swift`, `UI/Strings.swift`.
- **Constraints:** DESIGN §1 "stillness by default": the strip only appears on selection, never on
  hover.

### C-30 — Spoken announcements (deferred)
- **Closes:** F-38.
- **Change:** an optional voice for announcements and `say`/`ask` (SPEC §10), off by default, with
  `AVSpeechSynthesizer` or the reference app's FluidAudio approach.
- **Status:** not required for B's success. Listed so the inventory is fully covered; schedule
  after milestone M2.

---

## Traceability: every friction entry is closed

| F | Closed by | F | Closed by |
|---|---|---|---|
| F-01 | C-01 | F-26 | C-07, C-04 |
| F-02 | C-01 | F-27 | C-07 |
| F-03 | C-02, C-03 | F-28 | C-07 |
| F-04 | C-02, C-03 | F-29 | C-08, C-03 |
| F-05 | C-26 | F-30 | C-06 |
| F-06 | C-26 | F-31 | C-09, C-05 |
| F-07 | C-04 | F-32 | C-10, C-06 |
| F-08 | C-04 | F-33 | C-11, C-06 |
| F-09 | C-04, C-05 | F-34 | C-12 |
| F-10 | C-05, C-06 | F-35 | C-23 |
| F-11 | C-15 | F-36 | C-24 |
| F-12 | C-15 | F-37 | C-21 |
| F-13 | C-15 | F-38 | C-30 (deferred) |
| F-14 | C-17 | F-39 | C-20 |
| F-15 | C-16 | F-40 | C-20 |
| F-16 | C-16 | F-41 | C-19 |
| F-17 | C-17 | F-42 | C-18 |
| F-18 | C-29 | F-43 | C-22, C-05 |
| F-19 | C-03, C-05 | F-44 | C-03 |
| F-20 | C-03 | F-45 | C-25 |
| F-21 | C-13 | F-46 | C-19 |
| F-22 | C-14 | F-47 | C-05, C-15, C-03 |
| F-23 | C-14 | F-48 | C-13 |
| F-24 | C-13 | F-49 | C-27, C-05 |
| F-25 | C-28 | F-50 | C-17 |
