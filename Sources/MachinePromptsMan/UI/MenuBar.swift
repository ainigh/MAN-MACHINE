#if os(macOS)
import AppKit
import SwiftUI
import MpmCore
import MpmHost

/// DESIGN §4 menu bar: glyph plus countdown in tabular digits, width reserved for "00:00" so it never
/// jitters. Click opens the main window; right-click (or control-click) opens the menu.
@MainActor
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private unowned let model: AppModel

    static let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: Theme.Size.body, weight: .regular)
    static var digitsWidth: CGFloat {
        ceil((Countdown.reservedDigits as NSString).size(withAttributes: [.font: digitsFont]).width)
    }
    static var itemWidth: CGFloat { Theme.Space.s4 + Theme.menuGlyph + Theme.Space.s4 + digitsWidth + Theme.Space.s4 }

    init(model: AppModel) {
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: Self.itemWidth)
        super.init()
        guard let button = item.button else { return }
        let label = PassthroughHostingView(rootView: MenuBarLabel(controller: model.controller))
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.topAnchor.constraint(equalTo: button.topAnchor),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel(Strings.appName)
    }

    /// DESIGN §7: a reminder flashes the menu-bar item.
    func flash() {
        item.button?.highlight(true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.item.button?.highlight(false)
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = buildMenu()
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            model.showMainWindow()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let c = model.controller
        menu.addItem(entry(Strings.openWindow, #selector(openWindow)))
        menu.addItem(.separator())
        if c.sessionActive {
            menu.addItem(entry(Strings.endSession, #selector(endSession)))
        } else {
            menu.addItem(entry(Strings.startSession, #selector(startSession)))
        }
        menu.addItem(entry(Strings.transcript, #selector(showTranscript)))
        menu.addItem(entry(Strings.systemMonitor, #selector(showMonitor)))
        menu.addItem(.separator())
        menu.addItem(entry(Strings.testMode, #selector(toggleTestMode), on: c.testMode))
        menu.addItem(entry(Strings.mute, #selector(toggleMute), on: model.muted))
        menu.addItem(entry(Strings.openAtLogin, #selector(toggleLogin), on: model.opensAtLogin))
        if let v = model.updater.available {
            menu.addItem(.separator())
            menu.addItem(entry(Strings.updateTo(v.tag), #selector(update)))
        }
        menu.addItem(.separator())
        menu.addItem(entry(Strings.schedule, #selector(showSchedule)))
        menu.addItem(entry(Strings.settings, #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(entry(Strings.quit, #selector(quit), key: "q"))
        return menu
    }

    private func entry(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let on { i.state = on ? .on : .off }
        return i
    }

    @objc private func openWindow() { model.showMainWindow() }
    @objc private func startSession() { model.controller.send(.startSession); model.showMainWindow() }
    @objc private func endSession() { model.controller.send(.endSession) }
    @objc private func showTranscript() { model.showTranscript() }
    @objc private func showMonitor() { model.showMonitor() }
    @objc private func toggleTestMode() { model.setTestMode(!model.controller.testMode) }
    @objc private func toggleMute() { model.muted.toggle() }
    @objc private func toggleLogin() { model.setOpensAtLogin(!model.opensAtLogin) }
    @objc private func update() { model.updater.installAvailable() }
    @objc private func showSchedule() { model.showSchedule() }
    @objc private func showSettings() { model.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Ticks for a once-a-second countdown, laid on the phase's own second boundaries. A periodic
/// schedule started at an arbitrary instant shows each digit up to a second late, so the menu bar
/// would trail the ring (DESIGN §11: they agree to the second).
@MainActor
enum SecondTicks {
    /// One engine second in real time: 1 s, or 1/60 s in test mode. Reads `testMode` so toggling it
    /// reschedules the timeline (the clock itself is not observed).
    static func interval(_ c: SessionController) -> TimeInterval { c.testMode ? 1 / c.timeScale : 1 }

    /// A past instant a whole number of engine seconds before the phase ends, plus a hair, so each
    /// tick lands just after the digit changes. Reads the session, so a new phase reschedules.
    static func anchor(_ c: SessionController) -> Date {
        guard let end = c.store.session?.phaseEnd else { return .now }
        let realEnd = c.realDate(forEngine: end)
        let step = interval(c)
        let steps = (realEnd.timeIntervalSinceNow / step).rounded(.up) + 1
        return realEnd.addingTimeInterval(-steps * step + step / 100)
    }
}

/// A hosting view that lets clicks through to the status-bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MenuBarLabel: View {
    let controller: SessionController

    var body: some View {
        if controller.sessionActive {
            // Ticks only while something is counting (DESIGN §5 stillness; tasks/10 idle CPU).
            TimelineView(.periodic(from: SecondTicks.anchor(controller), by: SecondTicks.interval(controller))) { _ in
                content(MenuBarDisplay.make(controller.store.session, now: controller.now()))
            }
        } else {
            content(MenuBarDisplay.make(nil, now: controller.now()))
        }
    }

    private func content(_ d: MenuBarDisplay) -> some View {
        HStack(spacing: Theme.Space.s4) {
            MenuGlyph(glyph: d.glyph, tone: d.tone)
                .frame(width: Theme.menuGlyph, height: Theme.menuGlyph)
            Text(d.digits ?? "")
                .font(Theme.digits)
                .frame(width: StatusItemController.digitsWidth, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.s4)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.digits.map { "\(Strings.appName), \($0)" } ?? Strings.appName)
    }
}

struct MenuGlyph: View {
    let glyph: MenuBarDisplay.Glyph
    let tone: Tone

    var body: some View {
        switch glyph {
        case .ring(let fraction):
            ZStack {
                Circle().stroke(Color.primary.opacity(0.25), lineWidth: Theme.statusStroke)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tone == .neutral ? Color.primary : Theme.color(tone),
                            style: StrokeStyle(lineWidth: Theme.statusStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(Theme.statusStroke / 2)
        case .square:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary)
                .padding(Theme.Space.s4 - 1)
        case .dot:
            Circle()
                .fill(Theme.color(tone))
                .padding(Theme.Space.s4 - 1)
        }
    }
}
#endif
