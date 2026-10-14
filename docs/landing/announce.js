/* announce.js — the engine's voice.
 *
 * SPEC §6.9 fixes the wording of every announcement the engine (A, the Timekeeper) makes.
 * This module keeps that wording as variant 0 of every trigger and adds a few alternatives
 * that carry exactly the same facts, chosen by the context the engine already has: round,
 * z, x, seated time, the pair, the diff, and which reminder this is.
 *
 * Three rules keep it inside the spec:
 *  1. Variant 0 is always the §6.9 text. voice: "fixed" (the default) never leaves it.
 *  2. Every variant states the same numbers and names. Only the sentence around them moves.
 *  3. Selection is a hash of (session, round, trigger), never Math.random, so a replayed log
 *     speaks the same words. Invariant 12 holds: the model is never involved.
 *
 * Usage:
 *   announce("status_start", ctx)                       → { text, variant, key }
 *   announce("status_start", ctx, { voice: "varied" })
 *   variants("status_start", ctx)                       → every applicable text, 0 first
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Announce = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /* ---------- formatting, identical to the engine's ---------- */
  function pad2(n) { return String(n).padStart(2, "0"); }
  // Countdown digits: whole seconds, rounded up.
  function digits(s) { s = Math.max(0, Math.ceil(s - 1e-9)); return Math.floor(s / 60) + ":" + pad2(s % 60); }
  // Spoken-friendly lengths: 45 s, 1:30, 10 min, 1:05:00.
  function fmt(t) {
    var s = Math.round(t);
    if (s < 60) return s + " s";
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    if (h > 0) return h + ":" + pad2(m) + ":" + pad2(sec);
    if (sec === 0) return m + " min";
    return m + ":" + pad2(sec);
  }
  function n(x, one, many) { return x + " " + (x === 1 ? one : many); }
  function or(v, d) { return v == null || v === "" ? d : v; }

  /* ---------- deterministic choice ---------- */
  function hash(str) { // FNV-1a, 32-bit
    var h = 0x811c9dc5;
    for (var i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
    return h >>> 0;
  }

  /* ---------- the context the engine hands in ----------
   * All fields optional; each variant guards what it needs. Times in seconds.
   *   sessionId, round, R, q, G, Lb, Ls, Zmax
   *   z, x, elapsed, remaining, statusLen, seated
   *   doing, next, prevDoing, prevNext        node titles
   *   diff: [[title, from, to], ...]          this round's status changes
   *   reminderIndex, reminderCount            which reminder is firing
   *   reason: "stop" | "grace"                for stop
   *   held: { say: bool, proposals: int }     for strategy_start
   *   openCount                               for session_start
   *   message                                 for not_available
   */

  var WORD = { open: "open", doing: "doing", next: "next", blocked: "blocked", done: "done", crossed_out: "crossed out", crossed: "crossed out", "new": "new" };
  function diffLines(c) {
    return (c.diff || []).filter(function (l) { return l[1] !== "new"; })
      .map(function (l) { return l[0] + " " + WORD[l[1]] + " → " + WORD[l[2]]; });
  }

  /* ---------- the table ----------
   * Each trigger is a list. Index 0 is the spec text and has no guard; the rest may guard
   * on context with `when`. A variant that needs a field the context lacks simply does not apply.
   */
  function V(say, when) { return { say: say, when: when }; }
  var has = function () { var ks = arguments; return function (c) { for (var i = 0; i < ks.length; i++) if (c[ks[i]] == null || c[ks[i]] === "") return false; return true; }; };

  var T = {
    session_start: [
      V(function () { return "Session open. Commit to start."; }),
      V(function () { return "Session open. Choose Doing and Next, then commit."; }),
      V(function (c) { return "Session open: " + n(c.openCount, "open step", "open steps") + ". Commit to start."; }, has("openCount")),
      V(function () { return "Session open. Nothing runs until you commit."; })
    ],

    round_start: [
      V(function (c) { return "Round " + c.round + ". " + or(c.doing, "nothing") + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + ", starting now."; }),
      V(function (c) { return "Round " + c.round + ", as planned: " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + "."; },
        function (c) { return c.round > 1 && c.doing && c.doing === c.prevNext; }),
      V(function (c) { return "Round " + c.round + ". " + c.doing + " first, then " + c.next + ". " + fmt(c.R) + " on the clock."; }, has("doing", "next")),
      V(function (c) { return "Round " + c.round + ". " + c.doing + " doing, nothing next yet. " + fmt(c.R) + ", starting now."; },
        function (c) { return c.doing && !c.next; }),
      V(function (c) { return "Round 1. " + c.doing + " doing, " + or(c.next, "nothing") + " next. " + fmt(c.R) + ". First reminder at " + fmt(c.R / 2) + " left."; },
        function (c) { return c.round === 1 && c.doing; })
    ],

    reminder: [
      V(function (c) { return fmt(c.remaining) + " left."; }),
      V(function (c) { return fmt(c.remaining) + " left, halfway."; },
        function (c) { return c.reminderIndex === 0 && c.R && Math.abs(c.remaining - c.R / 2) < 1; }),
      V(function (c) { return "Last reminder: " + fmt(c.remaining) + ". Get ready to stop."; },
        function (c) { return c.reminderCount != null && c.reminderIndex === c.reminderCount - 1; }),
      V(function (c) { return fmt(c.remaining) + " to go."; },
        function (c) { return c.reminderCount == null || c.reminderIndex < c.reminderCount - 1; })
    ],

    time_up: [
      V(function () { return "Time's up."; }),
      V(function (c) { return "Time's up. " + n(c.Zmax - c.z, "snooze", "snoozes") + " left, " + fmt(c.G) + " to decide."; },
        function (c) { return has("Zmax", "z", "G")(c) && c.Zmax - c.z > 0; }),
      V(function (c) { return "Time's up. No snoozes left: stop."; },
        function (c) { return has("Zmax", "z")(c) && c.Zmax - c.z === 0; }),
      V(function (c) { return "Snooze over. Time's up."; },
        function (c) { return c.z > 0; })
    ],

    snooze_accepted: [
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ". " + fmt(c.q) + "."; }),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ", the last one. " + fmt(c.q) + "."; },
        function (c) { return c.z === c.Zmax; }),
      V(function (c) { return "Snooze " + c.z + " of " + c.Zmax + ": " + fmt(c.q) + " more. Away time doubles."; },
        function (c) { return c.z < c.Zmax; })
    ],

    snooze_refused: [
      V(function () { return "No snoozes left. Stop."; }),
      V(function (c) { return "All " + c.Zmax + " snoozes used. Stop."; }, has("Zmax"))
    ],

    stop: [
      V(function () { return "Stop."; }),
      V(function () { return "No answer. Stop."; }, function (c) { return c.reason === "grace"; }),
      V(function (c) { return "Stop. Round over at " + fmt(c.elapsed) + "."; }, function (c) { return c.reason !== "grace" && c.elapsed != null; })
    ],

    late_snooze: [
      V(function () { return "Too late. Stop."; }),
      V(function (c) { return "The " + fmt(c.G) + " window has passed. Stop."; }, has("G"))
    ],

    status_start: [
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Status, " + fmt(c.statusLen) + "."; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Nothing cleared. Status, " + fmt(c.statusLen) + "."; },
        function (c) { return c.x === 0; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ", " + n(c.x, "step", "steps") + " cleared. Status, " + fmt(c.statusLen) + "."; },
        function (c) { return c.x >= 2; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". Status, " + fmt(c.statusLen) + ": long enough to count as moving."; },
        function (c) { return c.statusLen != null && c.Lb != null && c.statusLen >= c.Lb; }),
      V(function (c) { return "Round over at " + fmt(c.elapsed) + ". " + n(c.z, "snooze", "snoozes") + ", so status is " + fmt(c.statusLen) + "."; },
        function (c) { return c.z > 0; }),
      V(function (c) { return "Round over early, at " + fmt(c.elapsed) + ". Status, " + fmt(c.statusLen) + "."; },
        function (c) { return c.R != null && c.elapsed != null && c.elapsed < c.R - 30 && !c.z; })
    ],

    strategy_start: [
      V(function (c) { return "Strategy, " + fmt(c.q) + "."; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". The model has " + n(c.held.proposals, "proposal", "proposals") + "."; },
        function (c) { return c.held && c.held.proposals > 0; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". The model has a note, no proposals."; },
        function (c) { return c.held && c.held.say && !c.held.proposals; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". Nothing from the model this round."; },
        function (c) { return c.held === null; }),
      V(function (c) { return "Strategy, " + fmt(c.q) + ". Choose nothing and " + c.prevDoing + " stays doing."; },
        function (c) { return !!c.prevDoing; })
    ],

    auto_commit: [
      V(function (c) { return "No choice made. " + or(c.doing, "nothing") + " doing, " + or(c.next, "nothing") + " next."; }),
      V(function (c) { return "No choice made. Keeping " + c.doing + " doing, " + or(c.next, "nothing") + " next."; },
        function (c) { return c.doing && c.doing === c.prevDoing; }),
      V(function (c) { return "No choice made. " + c.doing + " moves up to doing, " + or(c.next, "nothing") + " next."; },
        function (c) { return c.doing && c.doing === c.prevNext; })
    ],

    promote_next: [
      V(function (c) { return "Now doing " + c.doing + "."; }),
      V(function (c) { return "Now doing " + c.doing + ". Next is open."; }),
      V(function (c) { return c.prevDoing + " done. Now doing " + c.doing + "."; }, has("prevDoing"))
    ],

    no_doing: [
      V(function () { return "No doing node."; }),
      V(function () { return "No doing node. Set one, or finish."; })
    ],

    break_start: [
      V(function (c) { return "Seated " + fmt(c.seated) + ". Movement break, " + fmt(c.Lb) + "."; }),
      V(function (c) { return "Seated " + fmt(c.seated) + "; another round would pass " + fmt(c.Ls) + ". Movement break, " + fmt(c.Lb) + "."; }, has("Ls")),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Stand up: " + fmt(c.Lb) + " away, the plan is locked."; })
    ],

    continue: [
      V(function (c) { return "Seated " + fmt(c.seated) + ". Continue."; }),
      V(function (c) { return "Seated " + fmt(c.seated) + ". Continue; this is the last round before a break."; },
        function (c) { return has("R", "Ls")(c) && c.seated + 2 * c.R > c.Ls; }),
      V(function (c) { return "Seated " + fmt(c.seated) + ", " + fmt(c.Ls - c.seated) + " before a break. Continue."; },
        function (c) { return has("R", "Ls")(c) && c.seated + 2 * c.R <= c.Ls; })
    ],

    break_end: [
      V(function () { return "Sitting clock reset."; }),
      V(function (c) { return "Break over. Sitting clock reset. Round " + c.round + " next."; }, has("round"))
    ],

    not_available: [
      V(function (c) { return c.message || "Not available now."; })
    ]
  };

  /* ---------- API ---------- */
  function applicable(trigger, ctx) {
    var list = T[trigger];
    if (!list) throw new Error("announce: unknown trigger " + trigger);
    ctx = ctx || {};
    return list.filter(function (v, i) { return i === 0 || !v.when || v.when(ctx); });
  }
  function variants(trigger, ctx) {
    return applicable(trigger, ctx).map(function (v) { return v.say(ctx || {}); });
  }
  // opts.voice: "fixed" (spec text only) | "varied". opts.seed overrides the hash input.
  function announce(trigger, ctx, opts) {
    ctx = ctx || {}; opts = opts || {};
    var list = applicable(trigger, ctx);
    var key = opts.seed != null ? String(opts.seed) : [ctx.sessionId || "", ctx.round || 0, trigger, ctx.reminderIndex || 0, ctx.z || 0].join("|");
    var i = opts.voice === "varied" && list.length > 1 ? hash(key) % list.length : 0;
    var text = list[i].say(ctx);
    if (trigger === "status_start") { var d = diffLines(ctx); if (d.length) text += " " + d.join(", ") + "."; }
    return { text: text, variant: i, key: key };
  }

  return { announce: announce, variants: variants, TRIGGERS: Object.keys(T), fmt: fmt, digits: digits };
});
