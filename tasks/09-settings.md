# 09 — Settings

**Goal.** Everything configurable is in one window, with the derived values shown live. SPEC §6.1, §11.

## Deliverables
- `SettingsView.swift` with four tabs: Session (R, r, Ls, Lb, G with validation messages from
  `SessionConfig.validate`, and a live read-out of q, Zmax, the reminder times, and the status-length
  table from SPEC Protocol §9.1 for the chosen R and r), Model (from 07), Attention (from 08),
  General (open at login, sounds, test mode, logs folder, retention, export store as JSON).
- Session config changes apply at the next `start_session` (SPEC §11): the window says so when a
  session is running.
- Ls and Lb show a one-line note that they should be set from health guidance (SPEC §16 #1).

## Acceptance
- Entering R = 4 min, r = 4 shows reminders "2:00, 1:00 (three merged)" and q = 15 s, matching
  `ConfigTests.testReminderClampingTable`.
- An invalid config cannot be saved; the field shows the `ConfigError` description.
