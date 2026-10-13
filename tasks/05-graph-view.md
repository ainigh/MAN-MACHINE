# 05 — The graph

**Goal.** The mind map: the thing people will look at most. DESIGN §8 in full. SPEC §11 Graph row.

## Deliverables
- `Graph/Layout.swift`: Buchheim/Walker tidy tree over `Store` (pure; put it in MpmCore under
  `Layout/` with tests: determinism, no overlaps for 200 nodes, sibling order by `createdAt`).
- `Graph/GraphView.swift`: SwiftUI `Canvas` + overlay for hit-testing and text editing. Pan, zoom,
  fit. Layout transitions interpolated with the DESIGN §5 spring (keep a `[NodeID: CGPoint]` of
  current positions; animate toward the new layout).
- Node rendering per status, edges, dependency arcs, lock glyph, collapse of finished subtrees.
- Editing: inline title, drag to re-parent, context menu with every op (through the controller),
  ⌘Z/⇧⌘Z, ⌘N, ⌘⌫. Refusals show the `ValidationError` description in a 2 s inline toast.
- Slot picking: in IDLE/STRATEGY click the dot for D, ⌥-click for N; the session pane's Commit
  enables per DESIGN §11 using `Engine.validateCommit`.
- Proposal ghosts (data from `store.pending`; accept/reject plumbing lands in 07 but the rendering
  and the per-row buttons exist here, wired to the controller).

## Acceptance
- Layout tests green. A 150-node tree lays out in < 16 ms on an M1 (measure in a test).
- Screen recording: add five nodes, re-parent one, cross out a subtree, undo twice, redo once;
  everything animates per DESIGN §5 and nothing jumps.
- The same store rendered twice gives pixel-identical output (determinism).

## Out of scope
The grid (06). Model proposals arriving (07).
