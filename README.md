# Man-Machine

A timeboxed work companion for macOS. The human keeps a tree of work nodes; a deterministic engine
runs rounds with reminders, a snooze budget, a status phase sized by how the round went, a strategy
phase and a sitting limit; a language model is consulted once per round, at the boundary, and
nowhere else.

- `SPEC.md` — the specification (v2). Law.
- `DESIGN.md` — the visual and interaction bar.
- `CLAUDE.md` — standing directives for the builder.
- `tasks/` — the build, in order.
- `Sources/MpmCore` — the protocol: config, store, engine, projection, envelope parsing, simulator.
  Pure Swift, Foundation only, fully tested, builds on Linux.
- `Sources/MachinePromptsMan` — the macOS app (built by the tasks).

## Status

The core and the host are written and tested on Linux and macOS (`swift test`): the protocol, the
illustrated session replayed through the real controller at 600×, persistence and crash recovery,
model turns against a fake adapter (on time, late, never, prose only, locked nodes), the attention
policy and the graph layout. The SwiftUI app in `Sources/MachinePromptsMan/UI` builds on macOS only.

```
swift test                      # core + host, any platform
scripts/build-app.sh            # MachinePromptsMan.app, ad-hoc signed, host architecture
scripts/build-app.sh universal  # arm64 + x86_64, as CI builds it
```

## Install (once released)

```bash
gh api -H "Accept: application/vnd.github.raw" repos/ainigh/MAN-MACHINE/contents/install.sh | bash
```

Needs macOS 14 or newer. The app updates itself from GitHub releases (right-click the menu-bar item,
"Update to vX"); the store in `~/Library/Application Support/MachinePromptsMan/` is outside the
bundle and survives updates.

The app is ad-hoc signed, not notarized, so macOS may ask once after an install or update. To
notarize, a Developer ID holder runs, after `scripts/build-app.sh universal`:

```bash
codesign --force --deep --options runtime --sign "Developer ID Application: NAME (TEAMID)" build/MachinePromptsMan.app
ditto -c -k --keepParent build/MachinePromptsMan.app build/MachinePromptsMan.zip
xcrun notarytool submit build/MachinePromptsMan.zip --apple-id … --team-id TEAMID --wait
xcrun stapler staple build/MachinePromptsMan.app
```

Permissions: only Notifications, asked once at the first reminder.

Test mode runs time 60× faster (menu-bar right-click or Settings) and switches itself off after 30
minutes; a badge shows while it is on.

## Layout

```
Package.swift                       MpmCore (logic), MachinePromptsMan (app), tests
Sources/MachinePromptsMan/Host/    persistence, clocks, SessionController, model turns, scheduler,
                                    presentation values, graph geometry, updater (Foundation only)
Sources/MachinePromptsMan/UI/      SwiftUI + AppKit views (macOS)
Sources/MpmCore/
  Config.swift                      R, r, Ls, Lb, G and every derived formula       SPEC §6.1–6.2
  Node.swift                        node schema, statuses, ULIDs                    SPEC §3.1
  Ops.swift                         ops, authors, log entries, system state        SPEC §3.2–3.4, §5.1
  Store.swift                       apply with validation, slots, blocked, inverse SPEC §5
  Session.swift                     session state and the sitting clock            SPEC §6.3–6.4, §6.6.2
  Engine.swift                      the transition table, as a pure reducer        SPEC §6.5–6.8
  Announcement.swift                fixed wording                                   SPEC §6.9
  Metrics.swift                     x and the round diff from the log              SPEC §6.6.1
  Projection.swift                  triggers, initiative rules, project()          SPEC §7, §8.1–8.2
  Envelope.swift                    the four verbs and the degradation ladder      SPEC §4, §9.3
  Simulator.swift                   virtual clock driver; the host must match it
  AttentionPolicy.swift             quiet hours, budget, snooze, next clamping      SPEC §8.3
  Layout/TidyTree.swift             the graph's tidy tree layout                    DESIGN §8
Tests/MpmCoreTests/                 config table, illustrated session replay, store rules,
                                    envelope ladder, projection, invariant fuzz, layout, policy
Tests/MachinePromptsManTests/       persistence, host engine, model turns, scheduler, presentation
tasks/                              00 bootstrap … 11 release
scripts/build-app.sh                ad-hoc signed .app and .zip
.github/workflows/build.yml         test on Linux and macOS; release on main
```
