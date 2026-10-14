# 07 — Decisions D-1 to D-10: resolved

The author's answer to the ten open decisions in [README.md](README.md#decisions-the-author-must-make):

> Turn each decision into a setting and make the recommendation the default. Where a decision
> does not become a simple setting, adopt the recommendation.

- **Become settings (six):** D-1, D-2, D-4, D-6, D-8 (three settings), and the motion half of D-7.
- **Adopted as recommended (four):** D-3, D-5, D-9, D-10, and the token half of D-7.

All ten are **closed**. Tasks proceed on these answers. Do not wait for further confirmation.

**Also approved.** DESIGN.md amendments A-6, A-7 and A-9 (05 §21) were not among D-1 to D-10.
The author approved them afterwards, as proposed:

- **A-6 (DESIGN §6, session pane):** add the guide line, the key hints, the consequence caption and the footer help
  button. Task 23 edits DESIGN §6.
- **A-7 (DESIGN §8, graph):** add the slot chips, the action strip, level of detail by zoom, and double-click /
  ⌘0 to fit. Task 24 edits DESIGN §8.
- **A-9 (DESIGN §11):** append the 05 §19 detail checklist. Task 25 edits DESIGN §11.

Every amendment in 05 §21 is now approved; nothing in this plan waits on the author.

## How the settings are stored

- **Storage.** Every new setting is a field on `HostSettings` (`Sources/MachinePromptsMan/Host/HostSettings.swift`),
  saved to `host-settings.json`. None goes in the core `Settings`, which is frozen with the store
  schema (tasks/OPEN.md #2).
- **Decoding.** Each field gets a `CodingKeys` case and a `decodeIfPresent(...) ?? d.field` line in
  `init(from:)`, like the existing fields. A settings file written before the field existed must
  therefore decode to the default in this document.
- **Writing.** Settings change through `InitiativeScheduler.update { $0.field = value }`, the path
  today's host settings already use (`AppModel.muted`).
- **Labels.** Every label and caption below goes in `UI/Strings.swift`, using the exact wording
  given here.
- **Tests.** One decoding test covers all new fields at once:
  `HostSettingsTests.testNewSettingsDecodeToTheirDefaultsFromAnOldFile`. It decodes a JSON object
  that has none of the new keys, and asserts every default in the table below.
- **Spec record.** Each new default gets a row in SPEC §16 "Defaults chosen", citing this document.
  The row goes in the same PR as the task that builds it.

## Summary

| # | Decision | Resolution | Setting key | Default | Where | Task |
|---|---|---|---|---|---|---|
| D-1 | Refusal wording | Setting | `showEngineWording: Bool` | `false` (plain explanation) | Settings → General → Developer | 17 |
| D-2 | Quiet hours and a session you started | Setting | `quietHoursSilenceSessions: Bool` | `false` (sessions are heard) | Settings → Attention → Quiet hours | 20 |
| D-3 | When to ask for notifications | Adopted | — | Ask at the first Start session | — | 20 |
| D-4 | Who sees the Monitor | Setting | `developerTools: Bool` | `false` (hidden) | Settings → General → Developer | 18 |
| D-5 | Self-dismissing surfaces | Adopted | — | The one-time close note and toasts may dismiss themselves | DESIGN §7 (A-4) | 12 |
| D-6 | Menu-bar icon with no session | Setting | `idleMenuBarGlyph: IdleGlyph` (`.ring`, `.square`) | `.ring` | Settings → General → Appearance | 22 |
| D-7a | New colour tokens | Adopted | — | `ink3`, `hover`, `selection`, `focus` | DESIGN §3 (A-2) | 22 |
| D-7b | Countdown digit roll | Setting | `animateCountdownDigits: Bool` | `true` | Settings → General → Appearance | 22 |
| D-8 | Ollama JSON mode, keep-alive, warm-up | Settings (three) | `ollamaJSONMode: Bool`, `ollamaKeepAliveMinutes: Int`, `warmUpModel: Bool` | `true`, `30`, `true` | Settings → Model → Ollama | 14 |
| D-9 | Sounds on first run | Adopted | — (uses the existing `muted`) | Taken from the system's volume-feedback setting, once | First launch only | 25 |
| D-10 | "Step" or "node" in copy | Adopted | — | "step"; the root is "the goal" | `UI/Strings.swift` | 15, 17 |

---

## D-1 — Refusal wording → setting

- **Setting.** `showEngineWording: Bool`, default **`false`**.
- **Label.** "Show the engine's wording in messages".
- **Caption.** "For checking the app against its specification. Messages then show the engine's
  exact reason after the plain explanation."
- **Behaviour.**
  - **`false`:** a refusal toast shows the plain explanation from `RefusalExplanation` (C-13), with
    node titles and never node ids.
  - **`true`:** the toast shows the plain explanation, then a line break, then the engine's
    verbatim reason in 11 pt `ink2`.
  - **Either way:** the verbatim reason is always written to the monitor event detail, as C-13
    already requires.
- **Placement.** Inside the Developer group of Settings → General, so it is visible only when
  `developerTools` (D-4) is on. It keeps its value while hidden. Task 17 builds this setting
  before task 18 adds the Developer group; until then it sits at the end of General, ungated.
- **What it replaces.** tasks/05's "the engine's reason, verbatim". With this setting on, the
  person sees that wording exactly; it is still there for the author.
- **Test.** `RefusalExplanationTests.testEngineWordingIsAppendedOnlyWhenTheSettingIsOn`. This
  exercises a pure `ToastText.make(explanation:raw:showEngineWording:)` in Host; the UI renders
  the cases.

## D-2 — Quiet hours and a session you started → setting

- **Setting.** `quietHoursSilenceSessions: Bool`, default **`false`**.
- **Label.** "Quiet hours also silence session sounds".
- **Caption.** "When off, a session you start during quiet hours still sounds its reminders and
  Time's up."
- **Behaviour.**
  - **Quiet test.** `AppModel.quietNow` becomes a pure
    `SoundPolicy.silent(inQuietHours:sessionActive:quietHoursSilenceSessions:muted:)` in Host:
    silent if muted; otherwise silent if in quiet hours and (no session is running, or the setting
    is on).
  - **The indicator.** "Sounds quiet until 08:00" (C-21) shows whenever `silent` is true because of
    quiet hours, not because of Mute.
- **Placement.** Settings → Attention, in the Quiet hours section, under From and To.
- **What it replaces.** tasks/10's "quiet hours respected for sounds too". That remains true
  outside sessions, and inside a session when the setting is on.
- **Test.** `PresentationTests.testSoundPolicyTable`, which covers all 16 combinations of the
  four inputs.

## D-3 — When to ask for notification permission → adopted

- **Why there is no setting.** The permission prompt happens once in the app's life, so a
  preference for *when* it happens cannot be changed after it matters.
- **Behaviour.**
  - **When.** `AppModel` requests permission the first time the person starts a session (Start
    session button, Space, the menu item, or the menu-bar menu), before the engine handles
    `start_session`.
  - **What the person sees.** The reason is shown in the pane: "Reminders reach you as
    notifications when the window is hidden." Then `askedForNotifications` is set.
  - **Removed.** The request at the first reminder (`AppModel.announced`) is deleted.
- **Added for recovery.** Settings → General shows "Notifications: Allowed / Not allowed" from
  `UNUserNotificationCenter.getNotificationSettings`. When not allowed, it adds an
  "Open System Settings…" button that opens
  `x-apple.systempreferences:com.apple.Notifications-Settings.extension`.
- **What it replaces.** tasks/11's "asked once, at the first reminder". Update that sentence's
  comment on `HostSettings.askedForNotifications` to "at the first session start (07 D-3)".

## D-4 — Who sees the Monitor → setting

- **Setting.** `developerTools: Bool`, default **`false`**.
- **Label.** "Show developer tools".
- **Caption.** "Adds the Monitor, Test Mode and the engine's wording, for checking how the app
  behaves."
- **Behaviour when off:**
  - **Hidden:** the Monitor segment, System Monitor in the menu-bar menu, Monitor ⌘3, Test Mode
    in menus and in General, and the Developer group's other settings.
  - **Pane restore:** if `rightPane` was `.monitor`, it restores as `.graph`.
  - **Badge:** counts only person-facing problems (`ProblemPolicy.isPersonFacing`, C-18). Clicking
    it opens the place to fix the problem.
- **Behaviour when on:**
  - **Shown:** everything above.
  - **Badge:** counts every unseen warning and error, as today, and opens the Monitor. A developer
    sees everything; a person sees only what they can act on.
- **Test mode.** Turning `developerTools` off while test mode is on also turns test mode off
  (`AppModel.setTestMode(false)`). A hidden switch must never be left on.
- **Placement.** Settings → General, last section, "Developer".
- **What it replaces.** DESIGN §12's placement for everyone (amendment A-5, now approved).
- **Tests.**
  - `MonitorTests.testBadgeCountFollowsDeveloperTools`.
  - `PresentationTests.testRightPaneFallsBackWhenTheMonitorIsHidden` (pure
    `RightPaneRestore.resolve(saved:developerTools:)`).

## D-5 — Self-dismissing surfaces → adopted

- **Why there is no setting.** The close note appears once in the app's life. A toggle for it
  would be settings clutter for a one-time event.
- **Behaviour.**
  - **Close note (C-02):** shown once, for 4 s, then fades out over 240 ms.
  - **Toasts:** keep dismissing themselves with C-13's timing (2 s plus 60 ms per character, at
    most 8 s, held while the pointer is over them).
- **DESIGN.md change.** Amendment A-4 is approved. Task 12 edits DESIGN §7's sentence to: "No
  card ever fades out by itself except as listed above, the one-time close note, and toasts."

## D-6 — Menu-bar icon with no session → setting

- **Setting.** `idleMenuBarGlyph: IdleGlyph`, where `enum IdleGlyph: String, Codable { case ring,
  square }`. Default **`.ring`**.
- **Label.** "Menu-bar icon when no session runs". Choices "Ring" and "Square".
- **Behaviour.**
  - **`.ring`:** a 1.5 pt outline ring at 55% `primary` (05 §2).
  - **`.square`:** today's filled square.
  - **Within a session:** after Stop the square is shown until STATUS, whatever the setting.
- **Code.** `MenuBarDisplay.make` gains a parameter `idle: IdleGlyph`. The glyph enum gains an
  `.idleRing` case, and `MenuGlyph` draws it.
- **Placement.** Settings → General, section "Appearance".
- **DESIGN.md change.** Amendment A-1 is approved, with the setting: DESIGN §4 reads "a ring
  outline while no session runs (or a square, by setting); a square while stopped".
- **Test.** `PresentationTests.testIdleGlyphFollowsTheSetting`.

## D-7 — Tokens and the digit roll → tokens adopted, roll a setting

- **D-7a, tokens (adopted).**
  - **Why there is no setting.** Tokens are the design system itself, not a preference.
  - **What is added:** `ink3`, `hover`, `selection` and `focus` go into `Theme.swift` with the
    values and contrast table in 05 §4.
  - **DESIGN.md change.** Amendment A-2 is approved; task 22 adds the rows to DESIGN §3.
- **D-7b, digit roll (setting).**
  - **Setting.** `animateCountdownDigits: Bool`, default **`true`**.
  - **Label.** "Animate the countdown digits".
  - **Behaviour.** When on and Reduce Motion is off, the countdown uses
    `.contentTransition(.numericText(countsDown: true))`, a 120 ms roll. When off, or when Reduce
    Motion is on, digits change instantly. Reduce Motion always wins.
  - **Placement.** Settings → General → Appearance.
  - **DESIGN.md change.** Amendment A-3 is approved, with the setting: DESIGN §5 adds "Countdown
    digits may roll once per second (120 ms), by setting; never with Reduce Motion".

## D-8 — Ollama JSON mode, keep-alive and warm-up → three settings

All three are visible only when the adapter is Ollama, in Settings → Model, in a section titled
"Ollama".

| Key | Default | Label | Caption |
|---|---|---|---|
| `ollamaJSONMode: Bool` | **`true`** | "Ask for structured replies" | "Helps small models suggest changes to the plan. Turn off if replies come back empty." |
| `ollamaKeepAliveMinutes: Int` | **`30`** | "Keep the model loaded for" with a stepper, 0–240, step 5, in minutes | "0 lets Ollama decide. Longer means a faster first answer after a pause, and more memory in use." |
| `warmUpModel: Bool` | **`true`** | "Load the model when a session starts" | "Makes the first answer of the session arrive in time. Never runs during a round." |

- **Request body.** `OllamaAdapter.requestBody(prompt:model:jsonMode:keepAliveMinutes:)` builds it:
  - `"format": "json"` only when JSON mode is on;
  - `"keep_alive": "\(n)m"` only when `n > 0`; with 0 the key is omitted, so Ollama's own default
    applies.
- **Settings plumbing.** `OllamaAdapter` gets these from `ModelSettings`, so the three fields live
  on `ModelSettings` (inside `HostSettings.model`) with the same tolerant decoding.
- **Warm-up.** `ModelTurnCoordinator.warmUp()` returns at once when `warmUpModel` is false. Its
  state guard is not a setting: `mayWarmUp` stays true only for no session and IDLE (CLAUDE.md
  rule 3).
- **Spec record.** Three SPEC §16 rows, one per default, citing 07 D-8.
- **Tests.**
  - `ModelTurnTests.testOllamaRequestBodyFollowsTheSettings`: all four combinations of JSON mode
    on or off and keep-alive 0 or 30.
  - `ModelTurnTests.testWarmUpObeysTheSettingAndTheState`.

## D-9 — Sounds on first run → adopted

- **Why there is no setting.** This decides only the *initial value* of the existing "Sounds"
  setting (`muted`). After that, the person's own choice in Settings → General rules.
- **Behaviour.**
  - **When:** once, on the first launch with a fresh `host-settings.json`.
  - **How:** read the global default `com.apple.sound.beep.feedback`
    (`UserDefaults(suiteName: UserDefaults.globalDomain)`). If it is present and equal to `0`, start
    with `muted = true`. If it is `1` **or absent**, start with `muted = false`.
  - **Why absent means sounds on:** the signal "this person turned interface sounds off" exists
    only when the key is written explicitly. On many Macs the key is absent. Muting them would
    silence a timer app's main voice for people who never expressed that preference. This keeps
    the recommendation (follow the system preference) without guessing one.
  - **Telling the person:** if the result is muted, the first-run guide's last step adds one line:
    "Sounds are off, following your Mac's sound settings. Turn them on in Settings." Nothing is
    shown when sounds start on.
- **Code.** A pure `FirstRunSound.initialMuted(feedbackDefault: Int?) -> Bool` in Host.
- **DESIGN.md change.** Amendment A-8 is approved, covering D-2 and D-9. DESIGN §10 adds: "Quiet
  hours silence session sounds only by setting. On first run, sounds start muted only if the
  system's volume-feedback sound is explicitly off."
- **Test.** `PresentationTests.testFirstRunSoundFollowsAnExplicitSystemPreferenceOnly`, with inputs
  nil, 0 and 1.

## D-10 — "Step" or "node" → adopted

- **Why there is no setting.** A vocabulary toggle would split the copy in two and double every
  string.
- **Behaviour.** In every person-facing string the plan's items are "steps" and the root is "the
  goal":
  - "New Step", "Add Step", "Add a step under Fix login";
  - "Delete" for removable steps (C-14);
  - Help and the first-run guide.
- **Where "node" stays.**
  - Developer surfaces: the Monitor and the engine wording from D-1.
  - Logs, code identifiers and these documents.
- **Tasks.**
  - Task 15 writes the new strings for the first-run guide and Help.
  - Task 17 renames the existing strings: `Strings.newNode` → "New step", `menuAddChild` → "Add
    Step", `quickLogPlaceholder` → "Add a step under the selection", and every other occurrence.
  - The `scripts/check-strings.sh` gate from task 17 also fails on the word "node" in
    person-facing strings outside the developer section.

---

## What changes in the other documents

Applied in the same commit as this document:

- **README.md:** the decisions table now says "Resolved in 07", and its Status row shows them
  closed.
- **03-required-changes.md:** each "Author decision" line points to its resolution here.
- **04-task-plan.md:** rule 6 no longer waits on the author. Tasks 12, 14, 15, 17, 18, 20, 22 and
  25 each list the settings and adopted behaviours from this document in their deliverables.
- **05-design-improvements.md:** §21 marks amendments A-1 to A-5 and A-8 as approved. A-1, A-3
  and A-8 are approved with the settings above.
