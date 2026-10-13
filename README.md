# Machine-Prompts-Man

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

The core is written and tested (33 tests, including a replay of the protocol's illustrated session
and a seeded invariant fuzz). The app is not built yet; start at `tasks/00-bootstrap.md`.

```
swift test
```

## Install (once released)

```bash
gh api -H "Accept: application/vnd.github.raw" repos/ainigh/machine-prompts-man/contents/install.sh | bash
```

Needs macOS 14 or newer. The app is ad-hoc signed; macOS may ask once after an update.

## Layout

```
Package.swift                       MpmCore (logic), MachinePromptsMan (app), tests
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
Tests/MpmCoreTests/                 config table, illustrated session replay, store rules,
                                    envelope ladder, projection, invariant fuzz
tasks/                              00 bootstrap … 11 release
scripts/build-app.sh                ad-hoc signed .app and .zip
.github/workflows/build.yml         test on Linux and macOS; release on main
```
