# 03 — App shell, theme, menu bar

**Goal.** A menu-bar app with the main window, the design tokens, and the countdown in the menu bar.
DESIGN §2–§5, §4 menu bar line.

## Deliverables (`Sources/MachinePromptsMan/UI/`)
- `MachinePromptsManApp.swift` (SwiftUI `App` with `NSApplicationDelegateAdaptor`), replacing `main.swift`.
- `Theme.swift`: every token in DESIGN §3 as `Color`/`NSColor` with light/dark, the spacing scale,
  the type styles. Nothing in a view uses a literal color or size.
- `Strings.swift`: every UI string.
- Menu bar item: glyph + countdown, drawn with `NSStatusItem` and an `NSHostingView` (tabular digits,
  reserved width). Click opens the main window; right-click: Start session / End session / Settings / Quit.
- Main window: two panes per DESIGN §4, with placeholder content. Remembers frame and split.
- Open at login toggle (SMAppService), off by default.
- Launch flow: if no store, the window opens with the root node and an inline prompt to name the goal.

## Acceptance
- Screenshots in light and dark of the window and the menu bar at: no session, WORK with 4:32 left,
  BREAK. Digits do not shift width between 10:00 and 9:59 (record a 2 s clip).
- The app passes `swift build -c release` and launches as a menu-bar app with no dock icon until the
  window is shown.

## Out of scope
Real session controls (04), the graph (05).
