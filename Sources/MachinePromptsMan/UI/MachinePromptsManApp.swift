#if os(macOS)
import AppKit
import SwiftUI
import MpmCore
import MpmHost

/// A menu-bar app (LSUIElement): no dock icon until the main window is shown (tasks/03).
@main
struct MachinePromptsManApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        SwiftUI.Settings {
            if let model = AppModel.current {
                SettingsView(model: model)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let persistence = Persistence()
        let store: Store
        do {
            store = try persistence.load(now: Date())
        } catch {
            // Never overwrite a store we could not read (tasks/01). Say why and stop.
            let alert = NSAlert()
            alert.messageText = Strings.loadFailedTitle
            alert.informativeText = "\(error)"
            alert.addButton(withTitle: Strings.loadFailedQuit)
            alert.addButton(withTitle: Strings.showFiles)
            NSApp.activate()
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([persistence.storeURL])
            }
            NSApp.terminate(nil)
            return
        }
        let model = AppModel(store: store, persistence: persistence)
        self.model = model
        AppModel.current = model
        model.start(fresh: persistence.createdFresh)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.persistence.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showMainWindow()
        return true
    }
}
#endif
