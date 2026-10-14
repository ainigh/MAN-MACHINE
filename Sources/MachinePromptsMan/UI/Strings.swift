#if os(macOS)
import Foundation
import MpmCore
import MpmHost

/// Every string the UI shows, in one place (DESIGN §11). Proper punctuation, no exclamation marks,
/// no emoji (CLAUDE.md rule 8). Engine announcements are not here: they are `Announcement.text`,
/// shown as is (CLAUDE.md rule 6).
enum Strings {
    static let appName = "Machine Prompts Man"

    // MARK: Menu bar and app menu

    static let openWindow = "Open Window"
    static let startSession = "Start Session"
    static let endSession = "End Session"
    static let settings = "Settings…"
    static let schedule = "Schedule…"
    static let transcript = "Session Transcript"
    static let quit = "Quit Machine Prompts Man"
    static let openAtLogin = "Open at Login"
    static let testMode = "Test Mode (60×)"
    static let testModeBadge = "TEST 60×"
    static let mute = "Mute Sounds"
    static func updateTo(_ v: String) -> String { "Update to \(v)" }
    static let checkForUpdates = "Check for Updates"
    static let undo = "Undo"
    static let redo = "Redo"

    // MARK: Session pane (DESIGN §6)

    static func stateName(_ s: SessionState?) -> String {
        switch s {
        case nil, .end?: return "NO SESSION"
        case .idle?: return "IDLE"
        case .work?: return "WORK"
        case .timeUp?: return "TIME UP"
        case .snooze?: return "SNOOZE"
        case .status?: return "STATUS"
        case .strategy?: return "STRATEGY"
        case .sitCheck?: return "SIT CHECK"
        case .break?: return "BREAK"
        }
    }
    static func round(_ k: Int) -> String { "Round \(k)" }
    static func seated(_ t: TimeInterval) -> String { "Seated \(Announcement.fmt(t))" }
    static let doing = "Doing"
    static let next = "Next"
    static let vacant = "—"
    static let finish = "Finish"
    static func snooze(_ length: TimeInterval, left: Int) -> String { "Snooze · \(Announcement.fmt(length)) · \(left) left" }
    static let snoozeShort = "Snooze"
    static let stop = "Stop"
    static let commit = "Commit"
    static let endSessionButton = "End session"
    static let startSessionButton = "Start session"
    static func away(_ t: TimeInterval) -> String { "Away. Back in \(Countdown.digits(t))." }
    static let breakBody = "Stand up and move."
    static let commitIncomplete = "Choose a doing node and a next node: click a dot in the graph for doing, Option-click for next."
    static func diffRow(_ d: DiffLine) -> String { "\(d.from.rawValue) → \(d.to.rawValue)" }
    static let noSessionHint = "Start a session to run timed rounds."
    static let pickDoing = "Doing"
    static let pickNext = "Next"
    static let nextReminder = "Next reminder"
    static func remindsAt(_ t: TimeInterval) -> String { "at \(Countdown.digits(t))" }

    // MARK: Held model output (DESIGN §6, SPEC §8.6)

    static let fromTheModel = "Between rounds"
    static let acceptAll = "Accept all"
    static let rejectAll = "Reject"
    static let accept = "Accept"
    static let reject = "Reject"
    static let lock = "Lock"
    static let lockHelp = "Reject and never suggest changes to these nodes again."
    static let stale = "The map changed since this was proposed."
    static let answerPlaceholder = "Answer"
    static let send = "Send"
    static let messagePlaceholder = "Message"
    static let modelWorking = "Thinking."
    static let modelFailed = "The model did not answer."
    static func opSummary(_ s: String) -> String { s }

    // MARK: Graph and grid (DESIGN §8–§9)

    static let graph = "Graph"
    static let grid = "Grid"
    static let fit = "Fit"
    static let nameTheGoal = "Name the goal"
    static let goalPlaceholder = "What is this all for?"
    static let newNode = "New node"
    static let quickLogPlaceholder = "Add a node under the selection"
    static func updatedAgo(_ days: Int) -> String { days == 0 ? "updated today" : "updated \(days)d ago" }
    static func collapsed(_ n: Int) -> String { "\(n) more" }
    static let menuSetDoing = "Set as Doing"
    static let menuSetNext = "Set as Next"
    static let menuOpen = "Mark Open"
    static let menuDone = "Mark Done"
    static let menuCrossOut = "Cross Out"
    static let menuRestore = "Restore"
    static let menuAddChild = "Add Child"
    static let menuAddDependency = "Add Dependency…"
    static let menuRemoveDependency = "Remove Dependency"
    static let menuLock = "Lock (no suggestions)"
    static let menuUnlock = "Unlock"
    static let menuPin = "Pin"
    static let menuSnoozeNudges = "Snooze Nudges Until Tomorrow"
    static let menuResumeNudges = "Resume Nudges"
    static let menuUnpin = "Unpin"
    static let menuRemove = "Delete Typo"
    static let menuRename = "Rename"
    static let chooseDependency = "Click the node this one depends on. Esc cancels."
    static let columnTitle = "Title"
    static let columnStatus = "Status"
    static let columnDue = "Due"
    static let columnProgress = "Progress"
    static let columnLinks = "Links"
    static let columnUpdated = "Updated"
    static let addLink = "Add link"
    static let linkPlaceholder = "https://"
    static let noDue = "—"
    static let clearDue = "Clear"
    static func statusWord(_ s: Status) -> String { s == .crossedOut ? "crossed out" : s.rawValue }

    // MARK: Monitor panel

    static let monitor = "Monitor"
    static let systemMonitor = "System Monitor"
    static let monitorAll = "All parts"
    static let monitorShowAll = "Show all"
    static let monitorProblemsOnly = "Problems only"
    static let monitorMarkSeen = "Mark seen"
    static let monitorEmpty = "Nothing has happened yet."
    static let monitorQuiet = "Quiet"
    static let monitorPickEvent = "Select an event to see its detail."
    static func monitorRoute(_ from: String, _ to: String?) -> String { to.map { "\(from) → \($0)" } ?? from }
    static func monitorMeta(route: String, outcome: String, at: String, turn: String?) -> String {
        [route, outcome, at, turn.map { "turn \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    static func outcomeWord(_ o: Outcome) -> String {
        switch o {
        case .info: return "Hand-off"
        case .ok: return "Done"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
    static func monitorNodeLabel(_ title: String, working: String?, problems: Int) -> String {
        var s = title
        if let working { s += ", working: \(working)" }
        if problems > 0 { s += ", \(problems) unseen problem\(problems == 1 ? "" : "s")" }
        return s
    }
    static func problems(_ n: Int) -> String { n == 1 ? "1 problem" : "\(n) problems" }

    // MARK: Cards (DESIGN §7)

    static let timesUpTitle = "Time's up."
    static let stopWord = "Stop."

    // MARK: Notifications (tasks/11)

    static let notificationsWhy = "Reminders reach you as notifications when the window is hidden."

    // MARK: Settings (tasks/09)

    static let tabSession = "Session"
    static let tabModel = "Model"
    static let tabAttention = "Attention"
    static let tabGeneral = "General"
    static let roundLength = "Round length (R)"
    static let reminders = "Reminders per round (r)"
    static let sittingLimit = "Sitting limit (Ls)"
    static let breakLength = "Movement break (Lb)"
    static let grace = "Grace window (G)"
    static let healthNote = "Set from current health guidance."
    static let derived = "Derived"
    static let baseUnit = "Base unit q"
    static let snoozesPerRound = "Snoozes per round"
    static let reminderTimes = "Reminders"
    static func merged(_ n: Int) -> String { n == 2 ? "two merged" : n == 3 ? "three merged" : "\(n) merged" }
    static let statusTable = "Status length by snoozes (rows) and nodes cleared (columns)"
    static let appliesNextSession = "Changes apply at the next session."
    static let save = "Save"
    static let revert = "Revert"
    static let minutes = "min"
    static let seconds = "s"
    static let adapter = "Model"
    static let adapterNone = "None"
    static let adapterOllama = "Ollama (local)"
    static let adapterAnthropic = "Anthropic"
    static let modelName = "Model name"
    static let endpoint = "Endpoint"
    static let apiKey = "API key"
    static let apiKeyStored = "Stored in the Keychain."
    static let repairPass = "Allow one repair pass"
    static let contextNote = "Context note"
    static let contextNoteHelp = "A sentence or two the model sees with every turn."
    static let quietHours = "Quiet hours"
    static let from = "From"
    static let to = "To"
    static let maxNudges = "Nudges per day"
    static let rulesTitle = "Rules"
    static let snoozeSystem = "Snooze nudges"
    static let snoozeHour = "For 1 hour"
    static let snoozeTomorrow = "Until tomorrow"
    static let snoozeNextSession = "Until the next session"
    static let unsnooze = "Resume nudges"
    static func snoozedUntil(_ d: String) -> String { "Nudges snoozed until \(d)." }
    static let sounds = "Sounds"
    static let logsFolder = "Show Logs Folder"
    static let retention = "Keep logs"
    static let turnLogDays = "Turn log (days)"
    static let systemLogDays = "System log (days)"
    static let exportStore = "Export Store as JSON…"
    static let upcoming = "Upcoming"
    static let nothingScheduled = "Nothing scheduled."
    static let addSchedule = "Add"
    static let scheduleReasonPlaceholder = "What to look at"

    // MARK: Errors

    static let loadFailedTitle = "The store could not be opened"
    static let loadFailedQuit = "Quit"
    static let showFiles = "Show Files"
}
#endif
