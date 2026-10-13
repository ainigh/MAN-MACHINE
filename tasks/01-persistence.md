# 01 — Persistence

**Goal.** The store survives relaunches exactly, and the logs exist as files. SPEC §3.3, §12.

## Deliverables (`Sources/MachinePromptsMan/Host/Persistence.swift` and friends)
- Directory: `~/Library/Application Support/MachinePromptsMan/`.
  - `store.json` — snapshot of `Store` (whole value, pretty-printed, stable key order).
  - `patch-log.jsonl` — one `LogEntry` per line, appended on every apply. The snapshot includes
    `patchLog` too; on load, if the snapshot's `version` is behind the file's last `seq`, replay the
    missing entries' `ops` as `system` to catch up, and log that it happened.
  - `turn-log.jsonl`, `system-log.jsonl` — append-only, with retention per SPEC §12 (prune at launch).
- Atomic writes (write to temp, `rename`), on a background queue, debounced 250 ms, flushed on quit.
- `Persistence.load(now:) -> Store` creates a fresh store with root "Goal" when nothing exists.
- Migration hook: `schemaVersion` < 2 → run `Migration.v1to2` (SPEC §18.1); for now it throws
  "unsupported" with a clear message since no v1 stores exist in the wild. Leave the hook.
- **A session does not survive a relaunch** (SPEC §14: interruptions are `end_session`). On load, if
  `store.session` is non-nil and not `.end`, set it to `.end`, log it, and clear it. The map is intact.

## Acceptance
- Tests in `Tests/MachinePromptsManTests/PersistenceTests.swift` (new test target, macOS only):
  round-trip a store with a session; corrupt `store.json` → load from the log alone; retention prunes.
- Kill -9 during a burst of writes leaves either the old or the new file, never a torn one (write the
  test with a temp directory and a simulated crash between temp-write and rename).

## Out of scope
iCloud, sync, encryption.
