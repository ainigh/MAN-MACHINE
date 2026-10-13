# DESIGN.md — the bar

The app should feel like a precision instrument: quiet, exact, and pleasant to look at for hours.
Every decision below is concrete so that "polished" is testable. Where a task adds UI, it cites the
sections here it satisfies.

## 1. Principles

- **One idea per surface.** The session view is the clock. The graph view is the plan. Neither does
  the other's job; neither carries chrome it does not need.
- **Time is the hero.** The countdown is always legible at a glance, from across the room during a
  round and in the menu bar when the window is closed.
- **Stillness by default.** Nothing moves unless the state changed. No idle animation, no pulsing
  except the one defined in §5, no decorative gradients.
- **Exactness.** Durations shown are the engine's, formatted by `Announcement.fmt`. Never round
  differently in two places. Tabular numerals everywhere a number changes.
- **Restraint in color.** One accent per status, otherwise grayscale. Dark and light mode are both
  first-class; design in dark, verify in light.

## 2. Typography

- UI text: SF Pro (system). Sizes: 11 caption, 13 body, 15 title, 22 heading.
- Numbers that change (countdowns, counters, seated time): SF Mono or SF Pro Rounded with
  `.monospacedDigit()`. The big round countdown: 56 pt, weight medium, tracking -1.
- Node labels in the graph: 13 pt, single line, truncated with ellipsis at 28 characters, full title on hover.
- No bold for emphasis in running text. Use weight only for hierarchy.

## 3. Color tokens (define once in `UI/Theme.swift`)

| Token | Dark | Light | Used for |
|---|---|---|---|
| `bg` | #121214 | #F7F7F8 | window background |
| `surface` | #1B1B1F | #FFFFFF | cards, panels |
| `line` | #2C2C32 | #E3E3E8 | hairlines, 1 px |
| `ink` | #ECECF1 | #16161A | primary text |
| `ink2` | #9A9AA6 | #6E6E7A | secondary text |
| `doing` | #5B8DEF | #2F6BE0 | D slot, round ring |
| `next` | #8A7DF0 | #6A5CE8 | N slot |
| `done` | #4FB37E | #2E9B62 | done, x |
| `blocked` | #C98A3B | #B4762B | blocked, snooze count |
| `stop` | #E0655B | #D14E44 | time's up, hard stop |
| `break` | #4FAFC9 | #2F97B5 | movement break |

Status colors are used as 2 px strokes, small dots and text, not as fills, except the D node's fill
in the graph and the round ring. Crossed-out is `ink2` at 50% with a strikethrough. Done is `done`
at 70% with a 12 pt check glyph.

## 4. Layout

- Main window: 980 × 640 default, min 760 × 480. Two panes: session (left, fixed 300 pt) and graph
  (right, fills). A segmented control at the top right of the right pane switches Graph / Grid.
- Hairlines, not shadows, separate regions. Cards have 10 pt radius, 1 px `line` border, no shadow.
- Spacing scale: 4, 8, 12, 16, 24, 32. Nothing else.
- Menu bar: a glyph (a ring that empties as the round runs; a square while stopped; a dot in
  `break` during a break) plus the countdown in tabular digits. Width must not jitter: reserve
  for `00:00`.

## 5. Motion

- Durations: 120 ms for state color changes, 180 ms for layout shifts, 240 ms for a card entering.
  Easing: `easeOut` in, `easeIn` out. Springs only for the graph layout (response 0.4, damping 0.85).
- The round ring sweeps continuously (it is the one thing allowed to move), at 60 fps, driven by
  `TimelineView`, not a timer.
- The only pulse: the time-up card's border, once per second, during the 10 s grace window.
- No bounce, no overshoot, no fade-through-black, no slide from the edge of the screen.
- Reduce Motion honoured: layout changes become cross-fades, the ring still sweeps.

## 6. The session pane (states, top to bottom)

- **Header**: state name in caps 11 pt `ink2` ("WORK", "STATUS"), round number, seated time.
- **Ring**: 220 pt, 6 pt stroke in the state color, the countdown in the center. In STATUS the ring
  fills in `ink2` ("time away" reads as neutral); in BREAK in `break`.
- **Slots**: two rows, "Doing" and "Next", each the node title with a colored dot. Vacant reads "—".
- **Controls**: exactly the events allowed in this state (SPEC §6.8), nothing greyed out, nothing
  hidden behind a menu. WORK: Finish. TIME_UP: Snooze (with "2 of 3 left"), Stop. STATUS: nothing
  (the pane says "Away. Back in 1:30."). STRATEGY: Commit (enabled when D and N are chosen in the
  graph). IDLE: Commit. Always: End session, small, bottom.
- **Announcement line**: the last `Announcement.text`, 13 pt `ink2`, replaced in place with a 120 ms fade.
- **Round diff** (STATUS and STRATEGY only): the `DiffLine`s as "title  open → done" rows.
- **Held model output** (STRATEGY only, SPEC §8.6): a card with `say`, an `ask` input if present,
  and proposals as diff rows with Accept / Reject per row and for the whole. Expires at commit.

## 7. Cards (what pops up)

- **Reminder**: a thin strip at the top of the session pane and a menu-bar flash; no window. If the
  app is hidden, a system notification with the announcement text. Disappears at the next state change.
- **Time's up**: a 320 × 180 card centered on the main screen, above other windows. Countdown of the
  grace window as a 1 px bar along the bottom. Snooze and Stop as the only buttons. Stays until answered;
  if the grace window lapses it flips to "Stop." for 2 s and closes.
- **Hard stop / Stop**: same card, `stop` border, the one word, closes after 2 s.
- **Movement break**: a full-width band at the top of the screen in `break`, with the countdown.
  Blocks nothing (SPEC §16 #13) but is unmistakable.
- No card ever fades out by itself except as listed above.

## 8. The graph

- **Layout**: tidy tree (Buchheim/Walker), top-down, root at top, siblings ordered by `createdAt`.
  Deterministic: the same store always draws the same picture. Animated between layouts with the §5 spring.
- **Nodes**: pills, 28 pt tall, horizontal padding 12, radius 14. Fill `surface`, stroke `line`.
  D: fill `doing`, text white. N: stroke `next` 2 px. Blocked: stroke `blocked` dashed. Done: faded,
  check glyph. Crossed-out: strikethrough, 50%. Locked (`no_suggest`): a 10 pt lock glyph before the title.
- **Edges**: 1 px `line` cubic curves parent→child. Dependency edges: 1 px `blocked` dashed arcs with a
  small arrowhead, drawn behind nodes.
- **Proposals**: proposed changes drawn as ghosts: a new node at 50% with a dashed stroke; a status
  change as a second stroke in the proposed color; a move as a dashed edge to the proposed parent.
  Hover shows the `say` text. Accept applies with the layout spring.
- **Interaction**: click selects; double-click edits the title inline; drag to re-parent (drop target
  highlights); right-click for the op menu (statuses, cross out, restore, add child, add dependency,
  lock). ⌘Z / ⇧⌘Z undo and redo through the patch log. Scroll to pan, pinch to zoom, "Fit" button.
  During STRATEGY, clicking a node's dot sets D, ⌥-click sets N.
- **Done and crossed-out subtrees** collapse to a single pill with a count after 30 s unselected;
  click to expand. Collapsed state is view state, never store state.

## 9. The grid

- Rows: title, status (as a small colored word), due, progress bar (2 px), links count, updated.
  Inline edit on every cell except updated. Sorted by tree order; indentation shows depth.
- Quick-log at the bottom: a single text field; Enter adds a node under the selected one.

## 10. Sound

- Four sounds, all under 400 ms, all synthesized (no samples with character): reminder (one soft tick),
  time's up (two tones falling), stop (one low tone), round start (one tone rising). Volume follows the
  system. A setting mutes all. Nothing else makes a sound.

## 11. Micro-interactions that must exist (checklist for the polish task)

- Countdown digits do not jitter horizontally (tabular numerals, reserved width).
- Snooze button shows the remaining count and the length ("Snooze · 45 s · 2 left").
- Hovering a node shows its full title and `updated 3d ago` after 400 ms; never on touch of the pointer.
- The commit button enables the instant both slots are set and the engine would accept them; disabled
  with the refusal reason in a tooltip otherwise (from `Engine.validateCommit`).
- The ring's remaining arc and the menu bar digits agree to the second.
- Accepting a proposal animates the node into place; rejecting it fades the ghost in 120 ms.
- Keyboard: Space = Finish/Snooze/Commit for the current state, Esc = Stop at time-up, ⌘, settings,
  ⌘N new node under selection, ⌘⌫ cross out.
- Light/dark switch mid-session changes nothing but colors; no relayout.
- The window remembers size, position, split and zoom across relaunch.
- Every string in the UI exists in one place (`UI/Strings.swift`), spelled with proper punctuation and
  no exclamation marks.
