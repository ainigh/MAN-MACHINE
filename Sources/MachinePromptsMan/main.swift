// The macOS app shell. See tasks/03-app-shell.md. This file is replaced by the SwiftUI App in that task.
import Foundation
import MpmCore

#if canImport(AppKit)
import AppKit
print("MachinePromptsMan: app shell not built yet. See tasks/.")
#else
print("MachinePromptsMan core builds on Linux; the app needs macOS.")
#endif
