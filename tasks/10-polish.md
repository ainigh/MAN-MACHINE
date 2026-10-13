# 10 — Polish

**Goal.** Walk DESIGN §11 and the whole app with the eye of someone who will use it eight hours a day.

## Deliverables
- Every item in DESIGN §11 verified with a screen recording or a screenshot in the PR.
- Accessibility: VoiceOver labels on every control and node; the ring announces the remaining time
  every reminder; full keyboard operation of the session pane; contrast ≥ 4.5:1 for text (check
  `ink2` on `surface` in both modes and adjust the token if needed, in Theme.swift only).
- Performance: the graph at 300 nodes pans at 60 fps on an M1; the app idles at 0% CPU between ticks
  (no polling timers; `TimelineView` only while the ring is visible).
- Test mode (60×) toggle in the menu bar's right-click menu and in Settings, with a visible badge
  while on and auto-off after 30 minutes (reference app pattern).
- Mute toggle. Quiet hours respected for sounds too.
- First-run: name the goal, add three nodes, start a session, all from the keyboard, in under a minute.
- Remove anything that violates CLAUDE.md rule 8.

## Acceptance
- A 3-minute screen recording of a full round in real time, window and menu bar, light mode, that the
  author would be happy to show someone.
