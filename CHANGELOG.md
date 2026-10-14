# Changelog

Versions come from the git tag CI creates on `main` (`v0.0.<run>`). Newest first.

## Unreleased

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
