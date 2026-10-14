# Changelog

Versions come from the git tag CI creates on `main` (`v0.0.<run>`). Newest first.

## Unreleased

- Monitor panel (Graph / Grid / Monitor): the app's nine parts as a diagram. A dot travels an edge
  for each hand-off (event, tick, effect, patch, disk write, model turn), an arc shows work in
  progress (a model turn against its deadline), and each part shows its last outcome and unseen
  problems. Click a part to filter, click an event for its detail (turn prompt and raw output). A
  "N problems" badge appears in any pane; also opened from the menu bar's System Monitor item.
- Fixed: undo could reach across a commit and put a node back to `open`; accepting part of a
  proposal marked the rest stale and left `tmp:` references unresolvable; a queued initiative held
  back messages behind it; held turn ids misattributed after a relaunch; sound engine crashed after
  an output-device change and kept running when idle; time-up card and break band stayed up after
  End session; Doing/Next picks outlived an auto-commit; log retention setting was never applied;
  self-update could exit before the store was flushed.
- Added: snooze nudges for one node (graph context menu, SPEC §8.3); add a schedule entry by hand.
- Persistence: snapshot, patch log, turn and system logs; replay from the log; atomic writes.
- Host engine: clocks (system, 60× test mode, manual), timers from engine effects, wake handling,
  undo and redo through the patch log.
- Model turns: Ollama and Anthropic adapters, the prompt template, the degradation ladder with one
  repair pass, held output until STRATEGY, late and missing answers handled, proposals with accept,
  reject and lock.
- Outside a session: initiative rules every 15 minutes, attention policy (quiet hours, daily budget,
  snooze), schedule entries, model `next`.
- The app: menu-bar countdown, session pane and ring, cards, sounds, notifications, the graph, the
  grid, settings, schedule and transcript windows, self-update from GitHub releases.
