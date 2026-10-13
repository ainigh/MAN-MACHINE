# 00 — Bootstrap

**Goal.** The repository builds and tests on macOS and Linux, and CI does the same on every push.

## Deliverables
- `swift test` passes on macOS 14+ with Xcode 16 / Swift 6.
- `.github/workflows/build.yml` runs `swift test` on `macos-latest` and on `ubuntu-24.04`
  (install the Swift 6 toolchain), and on `main` runs `scripts/build-app.sh` and uploads
  `MachinePromptsMan.zip` as a release asset. (The workflow file is already present; verify it.)
- `scripts/build-app.sh` produces an ad-hoc signed `.app` from the executable target with an
  `Info.plist` (LSUIElement = YES: menu-bar app, no dock icon until a window opens; set
  `NSActivationPolicy` from the app). Universal on CI, host arch locally.
- `README.md` install line works: download the latest release zip into `~/Applications` and open it.

## Acceptance
- CI green on a PR with no code changes beyond this task.
- `swift build -c release` produces `MachinePromptsMan` that launches and prints nothing (the
  placeholder `main.swift` is replaced in task 03; for now it may exit immediately on macOS).

## Out of scope
Any UI. Any persistence. Notarization (see 11).
