# 04 — Session pane and cards

**Goal.** The full session experience without the model: start, rounds, reminders, time-up, snooze,
status, strategy, sitting check, break, end. DESIGN §6, §7, §10, §11.

## Deliverables
- `SessionPane.swift` per DESIGN §6, bound to `SessionController`. The ring via `TimelineView`.
- Cards per DESIGN §7: reminder strip, time-up card (grace bar), stop card, break band. Cards are
  separate `NSPanel`s at `.floating` level, non-activating, on every space.
- System notifications when the app is not frontmost (UNUserNotificationCenter), text = announcement.
- Sounds per DESIGN §10, synthesized with AVAudioEngine (a tiny `Tone.swift`), mute setting.
- Keyboard shortcuts per DESIGN §11.
- A "Session transcript" sheet showing `announcements` with timestamps (debug surface; keep it).

## Acceptance
- Walk the illustrated session by hand in test mode (60×) and record it: every announcement appears
  in the right place, the time-up card answers Snooze/Stop, the fourth snooze is refused, the 12-minute
  status phase shows "Away. Back in …", the break band appears after round 2.
- Reduce Motion on: no spring, ring still sweeps.
- With the window closed, a full round runs correctly from the menu bar and cards alone.

## Out of scope
Graph editing (05). Commit UI needs node pickers; until 05 lands, Commit may use two popup menus
listing live nodes by title.
