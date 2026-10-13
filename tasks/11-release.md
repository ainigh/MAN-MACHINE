# 11 — Release and self-update

**Goal.** Installable from a GitHub release, updates itself. Borrow the reference app's updater pattern.

## Deliverables
- `Updater.swift`: checks the latest release at launch and every 6 hours via `gh` if the repo is
  private, else the public API; downloads, swaps the bundle, relaunches. Shows the available version
  in the menu bar's right-click menu with "Update to vX".
- `install.sh` as in README. Ad-hoc signing acknowledged in README; notarization documented as a
  manual step with a Developer ID (do not block on it).
- Permissions: the app needs only Notifications. Ask once, at the first reminder, with a one-line
  explanation.
- CHANGELOG.md from this point on; version from the git tag.

## Acceptance
- A fresh Mac installs from the README line and runs the illustrated session in test mode.
- Updating from the previous release keeps the store intact (persistence test extended to real files).
