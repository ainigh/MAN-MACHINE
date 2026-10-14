# 05 — Design improvements: from correct to exceptional

**Premise.** Machine Prompts Man is client-facing and is meant to be the best app in its category,
remembered for its finish. [DESIGN.md](../../DESIGN.md) already sets a good bar: quiet, exact,
calm. This document keeps every principle in DESIGN.md and raises the execution: the details a
person feels without being able to name them. Every item is concrete enough to check from a
screenshot or a recording.

**How to use this document.**

- Sections are numbered; tasks in [04-task-plan.md](04-task-plan.md) cite them as "05 §n".
- Each item says **what**, **the number** (size, color, duration), and **why it matters**.
- Where an item changes DESIGN.md, it is listed in §21 as a proposed amendment. The author approves
  amendments; until then, DESIGN.md wins. When an amendment is approved, edit DESIGN.md in the same
  PR that builds it.
- Spacing uses DESIGN §4's scale only: 4, 8, 12, 16, 24, 32. Durations use DESIGN §5's values only:
  120, 180, 240 ms, plus the spring. New values below are flagged as amendments.

---

## 1. The bar

The app is right when:

1. **It reads in one glance.** Across the room: the time. Up close, in under a second: the state,
   what to do now, and what is next.
2. **It never surprises.** Every change on screen has a cause B just took or a timer B can see. No
   action does something larger than its label says (the F-27 lesson).
3. **It explains itself once, then gets out of the way.** First-run guidance, empty states and the
   guide line carry the teaching; nothing teaches twice.
4. **Every pixel is placed.** Text sits on baselines, icons are optically centred, hairlines land on
   whole pixels, numbers never jitter, colours mean one thing each.
5. **It feels native, and better than native.** Standard macOS behaviours (menus, shortcuts, focus
   rings, Escape, Undo, window restoration, accessibility) all work, so the custom parts can be
   distinctive without being strange.

---

## 2. Identity

- **App icon.** A rounded-square macOS icon (1024 px master, Apple's grid). Content: the ring at
  about 270° of sweep in the `doing` blue (#5B8DEF on the dark plate, #2F6BE0 on the light), 6/220
  stroke ratio as in the app, on a deep charcoal plate (#121214) with a 1 px inner highlight at 8%
  white along the top edge. No letters, no people, no clock hands. Supply the `.icns` set, including
  16 px and 32 px versions hand-tuned so the ring stays a ring (2 px minimum stroke at 16 px).
- **Name.** "Machine Prompts Man" everywhere a person sees it (C-26). Never "MPM" in the UI.
- **Menu-bar glyph** (amends DESIGN §4, see §21):
  - No session: a 1.5 pt *outline* ring, `primary` at 55% (instead of the filled square), so the
    item reads as "the ring app" even at rest. The square stays as the stopped state inside a
    session (after "Stop." until STATUS).
  - The 14 pt glyph is drawn as a template image so it follows the menu bar's light/dark tint and
    the "reduce transparency" setting.
  - Countdown digits: SF Pro 13 pt, `.monospacedDigit()`, baseline-aligned with the glyph centre
    minus 0.5 pt (optical correction; digits sit low otherwise).
  - Status colours appear in the menu bar only for TIME_UP (`stop`) and BREAK (`break`). Everything
    else is monochrome, so the menu bar does not compete with the person's other apps.

## 3. Typography

DESIGN §2 sizes stay (11, 13, 15, 22, 56). Refinements:

- **Tracking by size.** 11 pt caption: +0.2; 13 pt body: 0; 15 pt title: −0.1; 22 pt heading:
  −0.3; 56 pt countdown: −1 (DESIGN §2). SwiftUI `.tracking` on each `Theme` font, set once in
  `Theme.swift`.
- **Caps labels** (the state name "WORK"): 11 pt, weight `.medium`, tracking +0.8, `ink2`. Spaced
  caps read as a label rather than shouting. This is the only all-caps text in the app.
- **Line height.** Body copy in Help and the first-run guide: 13 pt on 20 pt lines (`lineSpacing(7)`
  relative to SF's default). The guide line (C-06): 13 pt on 18 pt.
- **Numbers.** Every changing number uses tabular figures (DESIGN §1). Also: durations in captions
  ("away 2:30") use tabular figures so the two numbers in "Stop now: away 2:30. Snooze: away 5:00."
  line up when they change.
- **The countdown** gets `.contentTransition(.numericText(countsDown: true))` in SwiftUI when
  Reduce Motion is off, so the digit change is a 120 ms vertical roll of the changed digit only.
  It is a state change once per second, which DESIGN §1 allows. (Amendment, §21.)
- **Weights.** Regular for text, medium for the countdown and caps labels, semibold only for the
  primary button title (system default). No bold in running text (DESIGN §2).
- **Truncation.** Titles truncate in the middle in the slot rows ("Write onbo…opy" keeps both ends
  recognisable) and at the tail in the graph pills (DESIGN §8). Always with the full title on hover.

## 4. Colour and tokens

DESIGN §3 tokens stay. Add, in `Theme.swift` only (amendment, §21):

| Token | Dark | Light | Used for |
|---|---|---|---|
| `ink3` | #6A6A76 | #8A8A94 | tertiary text: key hints, symbol captions, placeholder |
| `hover` | #FFFFFF at 4% | #000000 at 4% | row and pill hover wash |
| `selection` | `doing` at 14% | `doing` at 10% | selected row background in Grid and lists |
| `focus` | system `keyboardFocusIndicatorColor` | same | focus rings, never custom |

- **Contrast** (WCAG relative luminance, computed): `ink2` on `surface` is 6.2:1 dark (#9A9AA6 on
  #1B1B1F) and 5.0:1 light (#6E6E7A on #FFFFFF); on `bg` it is 6.7:1 dark and 4.7:1 light. All pass
  4.5:1 (tasks/10). `ink3` is for non-essential text only, at ≥ 3:1: #6A6A76 on #1B1B1F is 3.2:1,
  #8A8A94 on #FFFFFF is 3.4:1. Re-run the calculation for any token change and paste the table in
  the PR (§22).
- **One accent per meaning.** `doing` blue means "the Doing slot and the running round". It is not
  used for links, focus or generic buttons. Buttons use the system accent through
  `.borderedProminent` only for the single primary action in a surface.
- **Status colour as fill:** only the D pill and the ring (DESIGN §3). The reminder strip (PR #4) and
  any new chip in §6 use strokes and dots, never tinted fills.
- **Vibrancy.** The session pane and Settings use solid tokens, not materials; the graph canvas is
  `bg`. Glass and blur are reserved for nothing. (A precision instrument does not frost.)

## 5. Space, grid and alignment

- **One left edge.** In the session pane every text block starts at 16 pt from the pane edge; the
  ring is centred; the slot dots sit at 16 pt so their centres align with the left edge of the text
  above them plus 4 pt (optical).
- **Vertical rhythm.** Header to ring 24; ring to slots 24; slots to controls 16; controls to guide
  caption 8; caption to announcement 16; announcement to "Between rounds" 24. All on the scale.
- **Hairlines on whole pixels.** On 2× displays, 1 pt hairlines become 2 px: draw `Theme.hairline`
  as `1 / displayScale` where the design means "one physical pixel" (dividers, card borders), and
  1 pt where it means "one point" (graph edges at zoom 1). Decide per element; list in `Theme`.
- **Hit targets.** Every clickable thing is at least 24 × 24 pt, even when it looks smaller (the
  8 pt slot dot gets a 24 pt invisible hit circle; the Grid progress line gets the full row height).
- **Title bar.** The window uses a full-size content view (today). The traffic lights sit over the
  session pane; keep 32 pt of top padding there (today) and align the segmented control's
  vertical centre with the traffic lights' centre, not 12 pt from the top.

## 6. Picking Doing and Next (supports C-07)

- **Chips.** On a hovered or selected pill in IDLE or STRATEGY, two chips appear 8 pt to the right
  of the pill: "Doing" and "Next". Each chip: 20 pt tall, 8 pt horizontal padding, radius 10, 1 px
  stroke in `doing` / `next`, text 11 pt in the same colour, `surface` fill. The chip for the slot
  the node already holds shows a filled dot before its text instead.
- **Appearance:** chips fade in over 120 ms after the 400 ms hover delay (DESIGN §11) or at once on
  selection; never on a node that cannot be picked (finished, root); for a node that the engine would
  refuse as Doing (unfinished deps), the Doing chip is drawn at 40% and its tooltip gives the reason
  in plain words (C-13).
- **The slot rows** in the session pane show a 1 px dashed outline, radius 6, when they are a pick
  target (IDLE and STRATEGY), and a hover wash (`hover`). Clicking enters choose mode; the row's
  outline turns solid in the slot colour while choosing.
- **Confirmation of a pick:** the pill's dot gains the pick ring (today) and the slot row's title
  cross-fades to the new title in 120 ms. No other motion.

## 7. The session pane

- **Header:** state caps label left (§3); "Round 2" and "Seated 18 min" right, separated by a 4 pt
  middle dot in `ink3`, not by spacing alone.
- **Guide line** (C-06) directly under the header, 13 pt `ink2`, at most two lines, never truncated.
- **Ring:**
  - Reminder ticks: at each reminder time (`SessionConfig.reminders`), a 1 pt × 6 pt radial tick in
    `line` on the outside of the track, so B can see when the next tick will come. Ticks passed
    turn `ink3`.
  - Snooze budget: below the digits, `zMax` small dots (4 pt, 4 pt apart), filled `blocked` for each
    snooze used this round. Visible in WORK, TIME_UP and SNOOZE only.
  - Phase end: the trimmed arc has a round cap (today `.butt`); keep butt at the start and draw a
    2 pt `surface` gap before the cap so the moving end reads crisply against the track.
  - Inside the ring under the digits, an 11 pt `ink2` line names what the time counts: "left in the
    round", "left to answer", "away", "to plan", "break". Never more than three words.
- **Slot rows:** dot, label column (40 pt, today), title with middle truncation; in WORK the Doing
  title is `ink`, Next is `ink2` (what matters now is brighter).
- **Controls:** one primary button (`.borderedProminent`, control size `.large`) and at most one
  secondary (`.bordered`). The key hint (C-08) is inside the button, trailing, 11 pt `ink3`. The
  consequence caption (C-09) sits 8 pt below, 11 pt `ink2`, tabular.
- **Announcement line:** stays (DESIGN §6). When it repeats the reminder strip's text, the strip
  wins and the line shows the previous announcement instead, so the two never say the same thing.
- **Footer:** "End session" (C-12) left, "?" help button right, both 11 pt `ink2`, on one baseline,
  16 pt from the bottom.

## 8. Cards and transient surfaces

- **Time's up** (320 × 180, DESIGN §7): title "Time's up." 22 pt; grace caption "Stops in 7 s"
  (C-24) 11 pt `ink2` tabular; the two buttons; the consequence caption (C-09). The pulse stays the
  only pulse (DESIGN §5). The card animates in with a 240 ms opacity and a 4 pt upward settle
  (no scale), out with 240 ms opacity only.
- **Stop.**: same card; the word in `stop`; no buttons; the border solid `stop`; closes after 2 s.
- **Break band:** 44 pt; text centred as one line: "BREAK" caps label, "Stand up and move.",
  countdown; 24 pt between the three. Respect the notch: on a notched display, centre the text in
  the wider half of the menu-bar area so it is never cut.
- **Close note** (C-02): 280 pt wide, anchored 8 pt under the menu-bar item, arrow-less, `surface`,
  1 px `line`, 10 pt radius, 13 pt text. Fades in 240 ms, out 240 ms after 4 s.
- **Toasts:** bottom-centre of the right pane, max width 420 pt, wrap to two lines, then truncate
  with the full text on hover; refusal toasts have a 1 px `stop` border, guidance toasts `line`
  (PR #4). Stacking: a new toast replaces the old with a 120 ms cross-fade; never two at once.

## 9. The graph

- **Pills.** 28 pt tall (DESIGN §8). Add: a hover wash (`hover`) and the pointer cursor `.pointingHand`
  over the dot hit area only. Selected: today's 5 pt outset ring, but in `focus` colour when the
  graph has keyboard focus and `ink2` when it does not (macOS convention).
- **Level of detail.** Below 60% zoom, hide the check glyph and lock glyph and draw titles at a
  minimum effective size of 9 pt; below 35%, draw pills without text (just the shape and dot) so
  the overview stays clean. Above 200%, clamp text weight to regular (no faux bold from scaling).
- **Edges.** Today: 1 pt cubic curves. Add: edges into a finished subtree at 50% opacity, so live
  work stands out.
- **Drop target.** During drag, the target pill gets a 2 pt `doing` stroke and the would-be edge is
  previewed as a dashed `doing` curve from the target to the pointer.
- **Empty and sparse states.** With only the root: a ghost pill under it reading "Add a step  ⌘N"
  (50%, dashed, `ink2`), clickable. This replaces any empty-state illustration.
- **Action strip** (C-29): 28 pt tall, `surface`, 1 px `line`, radius 14, text buttons 11 pt with 12
  pt padding, separated by 1 px `line` dividers; centred under the selected pill, kept on screen.
- **Camera.** PR #4 eases Fit and focus over 180 ms. Add: Fit keeps 32 pt margins; a double-click
  on empty canvas fits; ⌘0 fits; ⌘+ and ⌘− zoom around the view centre in 25% steps, eased.
- **Hover card** (DESIGN §11): title, then "Doing · updated 3d ago" in `ink2`, then for blocked
  nodes "Waiting for Fix login" (C-13). 8 pt padding, radius 6.

## 10. Settings

- **Window:** 600 × 560, toolbar-style tabs with SF Symbols (`timer` Session, `cpu` Model,
  `bell.badge` Attention, `gearshape` General) — standard macOS Settings layout.
- **Session tab, "What a round looks like":** a 1-line timeline, full width, 24 pt tall: a `doing`
  bar for R with reminder ticks above it labelled 11 pt tabular ("5:00", "2:30", "1:15"), then a
  `line` segment for away time at the default (no snooze, one finished), then a `next` segment for
  planning. Below it: "Snooze length 1:15 · Up to 3 snoozes · Planning window 1:15". Updates live
  as fields change (120 ms cross-fade, no layout jump).
- **Validation:** invalid values show the reason inline under the field in `stop` 11 pt (today the
  error is a separate line), and Save stays disabled (PR #4).
- **Model tab:** the status line (C-15) with a 6 pt dot (`done` running, `blocked` not running,
  `stop` error), the model picker, Test with its result inline, never in an alert.
- **Footers:** the Save button is the only prominent button per tab, trailing; Revert is a plain
  button to its left, enabled only when something changed.

## 11. First-run guide and Help

- **Guide cards** (C-04): 400 pt wide, centred in the right pane, 24 pt padding, 22 pt heading,
  13/20 body, the field 15 pt. The "1 of 3" counter top right, 11 pt `ink3`. "Skip" bottom left,
  11 pt `ink2`. Moving to the next card: the current card's content cross-fades (180 ms); the card
  frame stays put and resizes with the layout spring if its height changes. No slide.
- **Steps list** (guide step 2): each added step appears as a pill preview in the card, 28 pt,
  exactly as it will look in the graph, so the transition to the graph is a recognition, not a
  surprise.
- **Help window:** 560 pt column, 32 pt margins, 22 pt section headings, 13/20 body, the cycle
  diagram drawn with the app's own components (ring segment colours, pills, hairlines) as a vector
  view, not a bitmap. Shortcut table in two columns, keys drawn as 11 pt key caps (1 px `line`
  rounded rectangles, 4 pt radius).

## 12. The grid

- Row height 28 pt to match the pills; 16 pt indentation per depth level (today) plus a 1 px
  vertical guide line in `line` per level, so depth reads without counting spaces.
- Status cell: the status word in its colour with a 6 pt dot before it (DESIGN §9 "small coloured
  word").
- Selected row: `selection` token background, no blue system highlight.
- Quick-log field: 13 pt, `ink3` placeholder that names the parent: "Add a step under Fix login".

## 13. The model's presence

- **"Between rounds" card:** `bg` fill on the `surface` pane (today), 12 pt padding, 10 pt radius.
  Heading 11 pt caps label "BETWEEN ROUNDS". The model's `say` in 13/20 `ink`; a question in 13
  `ink` with a 2 pt `next` bar on its left edge; proposals below a hairline.
- **Proposal rows:** the change as a sentence with titles in `ink` and the change in its status
  colour ("Mark **Fix login** as done" with "done" in `done`), Accept and Reject as 11 pt text
  buttons trailing, right-aligned on one column across rows. Accepting: the row's text turns
  `done` and the row collapses (180 ms) while the graph applies the change with the layout spring
  (DESIGN §11). Rejecting: the row fades out (120 ms) and the ghost fades in the graph at the same
  time.
- **Thinking:** during STATUS, a 1 pt `next` hairline under the "BETWEEN ROUNDS" heading fills left
  to right against the phase-turn deadline (the same idea as the monitor's work arc, DESIGN §12).
  No spinner.
- **Failure line:** 11 pt `stop` text, then the two actions as 11 pt text buttons (C-17).

## 14. The menu-bar menu

- Header (disabled item, 13 pt): "Work · 6:12 left" with the time tabular; second line 11 pt
  `ink2`: "Doing: Fix login". With no session: "No session" and "Click to open the window".
- Groups, in order: Open Window; session actions valid now (Start, Finish, Snooze, Stop, End
  Session…); Schedule…, Session Transcript; Mute Sounds, Open at Login; Settings… ⌘,; Quit ⌘Q.
  Developer items only in developer mode (C-19), in their own group.

## 15. Motion

DESIGN §5 stays. Additions:

| What | Duration | Easing | Reduce Motion |
|---|---|---|---|
| Countdown digit change | 120 ms numeric roll | easeOut | instant |
| Chips appear (§6) | 120 ms opacity | easeOut | instant |
| Guide card content change | 180 ms cross-fade | easeOut | instant |
| Proposal row accept collapse | 180 ms | easeOut | instant |
| Time's-up card settle | 240 ms, 4 pt rise + opacity | easeOut | opacity only |
| Camera ease (PR #4) | 180 ms | easeOut | instant |

Never: bounce, overshoot, scale-in, slide from an edge, staggered list entrances, looping
animations other than the ring and the one pulse.

## 16. Sound

DESIGN §10 stays: four synthesized sounds under 400 ms. Refinements:

- Master level −18 LUFS integrated, peaks below −6 dBFS, so the app is never the loudest thing on
  the Mac.
- A 3 ms fade-in and an exponential tail (today) plus a 10 ms fade-out at the end of each buffer, so
  no sound clicks at its end.
- Respect "Play feedback when volume is changed" being off as a hint that the person dislikes UI
  sounds: default Sounds off in that case on first run (author decision, §21).

## 17. Copy: the voice

- Second person, present tense, plain verbs. "Choose what comes next." not "Please select your next
  node."
- Short sentences, a full stop at the end of each, no exclamation marks (DESIGN §11), no "Oops", no
  praise, no exaggeration.
- Name things by what B sees: "step" for a node in guidance and Help ("node" stays in technical
  places: developer tools, logs). The root is "the goal".
- Numbers through `Announcement.fmt` or `Countdown.digits`, never written by hand.
- Errors say what happened and what to do, in that order: "Ollama is not running. Open the Ollama
  app, then check again."
- Every new string goes in `UI/Strings.swift`, grouped under the section of the screen it appears
  in.

## 18. Accessibility

- Every control has a VoiceOver label in plain words; the ring's value is "6 minutes 12 seconds left
  in the round", not "6:12".
- The graph's accessibility children (today) gain actions: "Make Doing", "Make Next", "Rename",
  "Mark done", "Cross out", exposed with `accessibilityAction(named:)`.
- Full keyboard path for every task in [06-verification-protocol.md](06-verification-protocol.md),
  including picking slots (D, N) and answering Time's up from the card (C-08).
- Increase Contrast: hairlines go to `ink2`, `ink3` maps to `ink2`.
- Dynamic type is not a macOS norm, but the window must survive the system "Larger text" setting in
  Accessibility → Display without clipping (test at the largest size).

## 19. The detail checklist

A builder ticks each with a screenshot (light and dark) or a recording:

1. No text anywhere touches its container edge; minimum 8 pt inset.
2. Every number that changes uses tabular figures; record the countdown for 10 s at 400% zoom: no
   horizontal movement.
3. The ring's arc end and the menu-bar digits change on the same frame (PR #4; record both).
4. Every hairline is crisp at 2× (zoom a screenshot to 800%: one or two solid pixels, no blur).
5. Every icon is optically centred in its control (SF Symbols with `.imageScale(.small)` and
   matching weight to adjacent text).
6. Focus rings appear on keyboard navigation and only then.
7. Hover states exist for every clickable custom element, and pointer cursors are correct.
8. No layout shift when the state changes, except the controls area (DESIGN §11 "no relayout" on
   appearance change: switch light/dark mid-session and record).
9. Every truncation has a hover with the full text.
10. Every empty state (no session, empty graph, no proposals, empty transcript, empty schedule, no
    monitor events) has copy that says what to do.
11. Window size, position, pane and zoom are restored after relaunch (DESIGN §11; zoom since PR #4).
12. Escape cancels every transient mode: rename, choosing a dependency, choosing a slot, the
    end-session confirm, the first-run guide step (back to the previous step).
13. Nothing is greyed out without a visible reason within 16 pt of it.
14. The app at 760 × 480 (the minimum window) still shows the whole session pane without
    scrolling the controls.

## 20. What not to do

- No onboarding carousel, no tour that dims the screen, no coach marks with arrows.
- No streaks, scores, badges, levels, or "you finished 5 rounds today".
- No illustrations of people, no mascots, no emoji, no confetti, no gradient backgrounds.
- No modal alerts for things that can be said inline.
- No colour that does not mean something.
- No second way of doing a thing that behaves differently from the first (the F-28 lesson).

## 21. Proposed amendments to DESIGN.md

The author decides each. A task that builds an amendment edits DESIGN.md in the same PR.

| # | DESIGN.md section | Today | Proposed | From |
|---|---|---|---|---|
| A-1 | §4 menu bar | "a square while stopped" | outline ring with no session; square only after Stop within a session | §2 |
| A-2 | §3 tokens | 11 tokens | add `ink3`, `hover`, `selection`, `focus` | §4 |
| A-3 | §5 motion | ring is the only continuous motion | allow a 120 ms numeric roll on countdown digits | §3, §15 |
| A-4 | §7 cards | "No card ever fades out by itself except as listed" | add the close note (C-02) and toasts to the list | §8 |
| A-5 | §12 monitor | third segment for everyone | developer mode only; badge shows person-facing problems | C-18, C-19 |
| A-6 | §6 session pane | header, ring, slots, controls, announcement | add the guide line, key hints, consequence caption, footer help | §7 |
| A-7 | §8 graph | interaction list | add slot chips, action strip, LOD, double-click to fit | §6, §9 |
| A-8 | §10 sound | "A setting mutes all" | quiet-hours behaviour for chosen sessions; first-run default from the system feedback setting | C-21, §16 |
| A-9 | §11 checklist | — | append the §19 checklist | §19 |

## 22. Evidence a builder must attach

For every PR that implements part of this document:

- Screenshots of each affected state, light and dark, at 100% and at the minimum window size.
- A screen recording of every motion it adds, with Reduce Motion off and on.
- For copy changes, a list of every changed string, before and after.
- For tokens, a contrast table for each new text colour on each background it is used on.
