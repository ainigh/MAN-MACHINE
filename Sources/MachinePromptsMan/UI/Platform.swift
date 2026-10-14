#if os(macOS)
import AppKit
import AVFoundation
import Security
import UserNotifications

/// The Anthropic API key lives in the Keychain, never in a settings file (tasks/07).
enum Keychain {
    static let service = "com.ainigh.machine-prompts-man"
    static let anthropicKey = "anthropic-api-key"

    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// System notifications when the window is not in front (tasks/04). Body = the announcement, unchanged.
@MainActor
final class Notifier {
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(_ text: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = Strings.appName
        content.body = text
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}

/// DESIGN §10: four sounds, each under 400 ms, synthesized. Volume follows the system.
@MainActor
final class Tones {
    enum Kind { case reminder, timesUp, stop, roundStart }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Kind: AVAudioPCMBuffer] = [:]
    private var stopTask: Task<Void, Never>?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers[.reminder] = make([(1_760, 1_760, 0.035)], level: 0.18)                 // one soft tick
        buffers[.timesUp] = make([(784, 784, 0.14), (523, 523, 0.18)], level: 0.25)     // two tones falling
        buffers[.stop] = make([(196, 196, 0.3)], level: 0.3)                             // one low tone
        buffers[.roundStart] = make([(440, 660, 0.22)], level: 0.22)                     // one tone rising
    }

    func play(_ k: Kind) {
        guard let b = buffers[k] else { return }
        // The engine stops itself when the output device changes; playing on a stopped engine raises.
        // Ask it, not a flag, and run it only around a sound so the app idles at 0% CPU (tasks/10).
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(b, at: nil, options: .interrupts)
        player.play()
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.player.stop()
            self.engine.stop()
        }
    }

    /// Segments of (start Hz, end Hz, seconds), each with a short attack and an exponential decay.
    private func make(_ segments: [(Double, Double, Double)], level: Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = AVAudioFrameCount(segments.reduce(0) { $0 + $1.2 } * rate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total), let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total
        var i = 0
        for (f0, f1, dur) in segments {
            let n = Int(dur * rate)
            var phase = 0.0
            for j in 0..<n {
                let t = Double(j) / rate
                let f = f0 + (f1 - f0) * Double(j) / Double(n)
                phase += 2 * .pi * f / rate
                let attack = min(1, t / 0.004)
                let decay = exp(-4 * t / dur)
                if i < Int(total) { ch[i] = Float(sin(phase) * attack * decay * level) }
                i += 1
            }
        }
        return buf
    }
}
#endif
