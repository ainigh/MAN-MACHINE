#if os(macOS)
import AppKit
import SwiftUI
import Observation
import ServiceManagement
import MpmCore
import MpmHost

enum RightPane: String, CaseIterable { case graph, grid }

/// The app's object graph: controller, model coordinator, scheduler, updater, windows, cards, sounds.
/// Views read state from here and send intents here or to the controller; none writes the store.
@MainActor
@Observable
final class AppModel {
    static var current: AppModel?

    let persistence: Persistence
    let controller: SessionController
    let coordinator: ModelTurnCoordinator
    let scheduler: InitiativeScheduler
    let updater: Updater

    var goalNeedsName = false
    /// A refusal shown inline for 2 s (tasks/05): the engine's reason, verbatim.
    var toast: String?
    /// D and N chosen in the graph for the next commit (DESIGN §8: click the dot / ⌥-click).
    var pickedDoing: NodeID?
    var pickedNext: NodeID?
    /// The graph pans here when the grid selects a node (tasks/06).
    var focusRequest: NodeID?
    var rightPane: RightPane {
        didSet { UserDefaults.standard.set(rightPane.rawValue, forKey: "rightPane") }
    }
    /// Starts inline title editing in the graph (⌘N, double-click).
    var editingNode: NodeID?

    @ObservationIgnored private var mainWindow: NSWindow?
    @ObservationIgnored private var auxWindows: [String: NSWindow] = [:]
    @ObservationIgnored private(set) var statusItem: StatusItemController?
    @ObservationIgnored private var cards: CardsController?
    @ObservationIgnored private let tones = Tones()
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let windowDelegate = MainWindowDelegate()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(store: Store, persistence: Persistence) {
        self.persistence = persistence
        let host = persistence.loadHostSettings()
        let coordinator = ModelTurnCoordinator(adapter: Self.makeAdapter(host.model), settings: host.model)
        let controller = SessionController(store: store, persistence: persistence, coordinator: coordinator)
        coordinator.controller = controller
        self.coordinator = coordinator
        self.controller = controller
        self.scheduler = InitiativeScheduler(controller: controller, coordinator: coordinator, persistence: persistence, settings: host)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        self.updater = Updater(currentVersion: version)
        self.rightPane = RightPane(rawValue: UserDefaults.standard.string(forKey: "rightPane") ?? "") ?? .graph
    }

    func start(fresh: Bool) {
        statusItem = StatusItemController(model: self)
        cards = CardsController(model: self)
        controller.announcementObservers.append { [weak self] a in self?.announced(a) }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.handleWake() }
        })
        // The monitor runs on the main thread; the closure is formed here, on the main actor.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        scheduler.start()
        updater.log = { [weak self] s in self?.controller.log(.persistence, s) }
        updater.start()
        if fresh {
            goalNeedsName = true
            showMainWindow()
        }
    }

    var hostSettings: HostSettings { scheduler.settings }

    var muted: Bool {
        get { scheduler.settings.muted }
        set { scheduler.update { $0.muted = newValue } }
    }

    // MARK: Windows

    func showMainWindow() {
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainView(model: self))
            host.sizingOptions = [.minSize]
            let w = NSWindow(contentViewController: host)
            w.title = Strings.appName
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentMinSize = Theme.windowMin
            w.delegate = windowDelegate
            // DESIGN §11: the window remembers its size and position across relaunch.
            if !w.setFrameUsingName(Self.mainFrameName) {
                w.setContentSize(Theme.windowDefault)
                w.center()
            }
            w.setFrameAutosaveName(Self.mainFrameName)
            mainWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    var mainWindowVisible: Bool { mainWindow?.isVisible == true && NSApp.isActive }

    func showSettings() { showAux("settings", title: Strings.settings.replacingOccurrences(of: "…", with: ""), SettingsView(model: self)) }
    func showSchedule() { showAux("schedule", title: Strings.schedule.replacingOccurrences(of: "…", with: ""), ScheduleView(model: self)) }
    func showTranscript() { showAux("transcript", title: Strings.transcript, TranscriptView(controller: controller)) }

    private func showAux<V: View>(_ key: String, title: String, _ view: V) {
        if auxWindows[key] == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = title
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = windowDelegate
            w.center()
            auxWindows[key] = w
        }
        NSApp.setActivationPolicy(.regular)
        auxWindows[key]?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static let mainFrameName = "MainWindow"

    // MARK: Session intents

    /// D and N for the commit: the picks if made, else the current slots (DESIGN §11).
    var commitDoing: NodeID? { pickedDoing ?? controller.store.doing?.id }
    var commitNext: NodeID? { pickedNext ?? controller.store.next?.id }
    var commitCheck: CommitCheck { CommitCheck.evaluate(doing: commitDoing, next: commitNext, store: controller.store) }

    func commit() {
        guard case .ready = commitCheck, let d = commitDoing, let n = commitNext else { return }
        controller.send(.commit(doing: d, next: n))
        pickedDoing = nil
        pickedNext = nil
    }

    func pick(doing id: NodeID) {
        pickedDoing = id
        if pickedNext == id { pickedNext = nil }
    }

    func pick(next id: NodeID) {
        pickedNext = id
        if pickedDoing == id { pickedDoing = nil }
    }

    var canPickSlots: Bool { controller.state == .idle || controller.state == .strategy }

    func startSession() { controller.send(.startSession) }

    func setTestMode(_ on: Bool) {
        controller.setTestMode(on, autoOffAfter: Double(hostSettings.testModeLimitMinutes) * 60)
    }

    // MARK: Graph and grid intents

    /// Applies a Man patch. A refusal is shown for 2 s with the engine's reason (tasks/05).
    @discardableResult
    func perform(_ ops: [Op]) -> ApplyResult? {
        do {
            return try controller.apply(ops)
        } catch {
            show(toast: "\(error)")
            return nil
        }
    }

    func nameGoal(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if perform([.updateNode(id: controller.store.rootID, fields: NodeFields(title: t))]) != nil { goalNeedsName = false }
    }

    /// ⌘N: a new node under the selection (or the root), ready to be named.
    func addChild(under parent: NodeID? = nil, title: String = Strings.newNode) {
        let p = parent ?? controller.selection ?? controller.store.rootID
        guard let r = perform([.add(title, under: p, tmp: "n")]), let id = r.entry.assignedIDs["n"] else { return }
        controller.selection = id
        editingNode = id
    }

    func rename(_ id: NodeID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, controller.store.nodes[id]?.title != t else { return }
        perform([.updateNode(id: id, fields: NodeFields(title: t))])
    }

    func crossOutSelection() {
        guard let id = controller.selection else { return }
        perform([.crossOut(id: id)])
    }

    /// Up: parent. Down: first child. Left and right: previous and next sibling.
    func moveSelection(_ keyCode: UInt16) {
        let store = controller.store
        guard let cur = controller.selection, let node = store.nodes[cur] else {
            controller.selection = store.rootID
            return
        }
        let siblings = node.parent.map { store.children(of: $0).map(\.id) } ?? [cur]
        let i = siblings.firstIndex(of: cur) ?? 0
        switch keyCode {
        case 126: if let p = node.parent { controller.selection = p }
        case 125: if let c = store.children(of: cur).first { controller.selection = c.id }
        case 123: if i > 0 { controller.selection = siblings[i - 1] }
        case 124: if i + 1 < siblings.count { controller.selection = siblings[i + 1] }
        default: break
        }
        focusRequest = controller.selection
    }

    func undo() { do { try controller.undo() } catch { show(toast: "\(error)") } }
    func redo() { do { try controller.redo() } catch { show(toast: "\(error)") } }

    func show(toast text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Motion.toast)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Model settings (tasks/07)

    static func makeAdapter(_ s: ModelSettings) -> ModelAdapter {
        switch s.kind {
        case .none: return NullAdapter()
        case .ollama:
            guard let url = URL(string: s.ollamaEndpoint) else { return NullAdapter() }
            return OllamaAdapter(endpoint: url, model: s.ollamaModel)
        case .anthropic:
            guard let key = Keychain.read(Keychain.anthropicKey), !key.isEmpty else { return NullAdapter() }
            return AnthropicAdapter(apiKey: key, model: s.anthropicModel, effort: s.anthropicEffort)
        }
    }

    func applyModelSettings(_ s: ModelSettings, apiKey: String?) {
        if let apiKey { Keychain.write(Keychain.anthropicKey, apiKey) }
        scheduler.update { $0.model = s }
        coordinator.setAdapter(Self.makeAdapter(s), settings: s)
        controller.log(.adapter, "model set to \(s.kind.rawValue)")
    }

    // MARK: Open at login (tasks/03), off by default

    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            controller.log(.persistence, "open at login: \(error)")
        }
    }

    // MARK: Announcements → sound, cards, notifications, VoiceOver (DESIGN §7, §10; tasks/10–11)

    private var quietNow: Bool {
        AttentionPolicy.quietHoursEnd(containing: Date(), settings: controller.store.settings) != nil
    }

    private func announced(_ a: TimedAnnouncement) {
        if !muted && !quietNow {
            switch a.announcement {
            case .reminder: tones.play(.reminder)
            case .timesUp: tones.play(.timesUp)
            case .stop, .noSnoozesLeft, .tooLate: tones.play(.stop)
            case .roundStart: tones.play(.roundStart)
            default: break
            }
        }
        cards?.handle(a)
        if case .reminder = a.announcement {
            statusItem?.flash()
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: a.text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            if !hostSettings.askedForNotifications {
                // tasks/11: ask once, at the first reminder, with one line saying why.
                scheduler.update { $0.askedForNotifications = true }
                show(toast: Strings.notificationsWhy)
                notifier.requestPermission()
            }
        }
        if !mainWindowVisible, Self.notifies(a.announcement) {
            notifier.post(a.text)
        }
    }

    static func notifies(_ a: Announcement) -> Bool {
        switch a {
        case .reminder, .timesUp, .stop, .noSnoozesLeft, .statusStart, .strategyStart, .movementBreak, .sittingClockReset, .autoCommit:
            return true
        default:
            return false
        }
    }

    // MARK: Keyboard (DESIGN §11)

    /// Space = Finish/Snooze/Commit (Start with no session), Esc = Stop at time-up, ⌘N, ⌘⌫, ⌘Z, ⇧⌘Z;
    /// arrows walk the graph, Return renames, D and N pick the slots. Never while typing.
    private func handleKey(_ e: NSEvent) -> Bool {
        guard let w = NSApp.keyWindow, w === mainWindow else { return false }
        if w.firstResponder is NSText { return false }
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (e.keyCode, mods) {
        case (49, []):                                   // space
            switch controller.state {
            case .work?, .snooze?: controller.send(.finish)
            case .timeUp?: controller.send(.snooze)
            case .idle?, .strategy?: commit()
            case nil: startSession()
            default: return false
            }
            return true
        case (2, []) where canPickSlots:                 // d: the selection is Doing for the commit
            guard let id = controller.selection else { return false }
            pick(doing: id)
            return true
        case (45, []) where canPickSlots:                // n: the selection is Next for the commit
            guard let id = controller.selection else { return false }
            pick(next: id)
            return true
        case (123, []), (124, []), (125, []), (126, []): // arrows walk the tree (tasks/10: keyboard only)
            guard rightPane == .graph else { return false }
            moveSelection(e.keyCode)
            return true
        case (36, []) where controller.selection != nil && rightPane == .graph:   // return renames
            editingNode = controller.selection
            return true
        case (53, []):                                   // escape
            guard controller.state == .timeUp else { return false }
            controller.send(.stop)
            return true
        case (45, [.command]):                           // ⌘N
            addChild()
            return true
        case (51, [.command]):                           // ⌘⌫
            crossOutSelection()
            return true
        case (6, [.command]):                            // ⌘Z
            undo()
            return true
        case (6, [.command, .shift]):                    // ⇧⌘Z
            redo()
            return true
        default:
            return false
        }
    }
}

/// Back to a menu-bar-only app when the last window closes (LSUIElement).
@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            if !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
#endif
