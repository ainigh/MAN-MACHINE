# 06 — The grid

**Goal.** The working surface for quick edits. DESIGN §9.

## Deliverables
- `GridView.swift`: `Table` or a custom list with inline editing per cell, tree order with indentation,
  status as a colored word with a popup, progress as a 2 px bar with a slider on click, due as a date
  picker, links as a count with a popover listing them (open in browser, add, remove).
- Quick-log field: Enter adds a node under the selection (or root), stays focused for the next one.
- Selection is shared with the graph (one `selection: NodeID?` on the controller).

## Acceptance
- Every edit goes through `controller.apply`; a refused edit reverts the cell and shows the reason.
- Tab moves across editable cells; arrow keys move rows; the graph pans to the selected node when
  the pane is visible.
