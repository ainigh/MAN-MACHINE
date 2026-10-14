#if os(macOS)
import AppKit
import SwiftUI
import MpmHost

/// DESIGN §2–§5, defined once. No view uses a literal color, size, spacing or duration.
enum Theme {

    // MARK: Color (DESIGN §3)

    static let bg = dynamic(dark: 0x121214, light: 0xF7F7F8)
    static let surface = dynamic(dark: 0x1B1B1F, light: 0xFFFFFF)
    static let line = dynamic(dark: 0x2C2C32, light: 0xE3E3E8)
    static let ink = dynamic(dark: 0xECECF1, light: 0x16161A)
    static let ink2 = dynamic(dark: 0x9A9AA6, light: 0x6E6E7A)
    static let doing = dynamic(dark: 0x5B8DEF, light: 0x2F6BE0)
    static let next = dynamic(dark: 0x8A7DF0, light: 0x6A5CE8)
    static let done = dynamic(dark: 0x4FB37E, light: 0x2E9B62)
    static let blocked = dynamic(dark: 0xC98A3B, light: 0xB4762B)
    static let stop = dynamic(dark: 0xE0655B, light: 0xD14E44)
    static let rest = dynamic(dark: 0x4FAFC9, light: 0x2F97B5)       // DESIGN token `break`
    /// Text on a filled `doing` pill (DESIGN §8).
    static let onFill = Color.white

    static func color(_ tone: Tone) -> Color {
        switch tone {
        case .doing: return doing
        case .next: return next
        case .done: return done
        case .blocked: return blocked
        case .stop: return stop
        case .rest: return rest
        case .neutral: return ink2
        }
    }

    /// Monitor outcomes (the monitor panel): a hand-off is `doing` blue, success `done`, trouble `blocked` or `stop`.
    static func color(_ outcome: Outcome) -> Color {
        switch outcome {
        case .info: return doing
        case .ok: return done
        case .warning: return blocked
        case .error: return stop
        }
    }

    static func nsColor(_ tone: Tone) -> NSColor { NSColor(color(tone)) }

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    // MARK: Type (DESIGN §2)

    enum Size {
        static let caption: CGFloat = 11
        static let body: CGFloat = 13
        static let title: CGFloat = 15
        static let heading: CGFloat = 22
        static let countdown: CGFloat = 56
        static let lockGlyph: CGFloat = 10
        static let checkGlyph: CGFloat = 12
    }

    static let caption = Font.system(size: Size.caption)
    static let body = Font.system(size: Size.body)
    static let title = Font.system(size: Size.title)
    static let heading = Font.system(size: Size.heading)
    static let countdown = Font.system(size: Size.countdown, weight: .medium).monospacedDigit()
    static let countdownTracking: CGFloat = -1
    static let digits = Font.system(size: Size.body).monospacedDigit()
    static let captionDigits = Font.system(size: Size.caption).monospacedDigit()
    static let nodeLabel = Font.system(size: Size.body)
    static let nodeLabelMaxChars = 28
    /// Model prompts and raw output in the monitor's detail pane.
    static let mono = Font.system(size: Size.caption, design: .monospaced)

    // MARK: Space (DESIGN §4)

    enum Space {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
    }

    // MARK: Shape and layout (DESIGN §4, §6, §8)

    static let cardRadius: CGFloat = 10
    static let hairline: CGFloat = 1
    static let statusStroke: CGFloat = 2
    static let sessionPaneWidth: CGFloat = 300
    static let windowDefault = CGSize(width: 980, height: 640)
    static let windowMin = CGSize(width: 760, height: 480)
    static let ringDiameter: CGFloat = 220
    static let ringStroke: CGFloat = 6
    static let pillHeight: CGFloat = 28
    static let pillPadding: CGFloat = 12
    static let pillRadius: CGFloat = 14
    static let dotSize: CGFloat = 8
    static let timeUpCard = CGSize(width: 320, height: 180)
    static let graceBar: CGFloat = 1
    static let menuGlyph: CGFloat = 14

    // MARK: Monitor panel

    enum MonitorPanel {
        static let node = CGSize(width: 148, height: 44)
        static let nodeMinWidth: CGFloat = 96
        static let diagramMinHeight: CGFloat = 260
        static let inspectorHeight: CGFloat = 240
        static let detailWidth: CGFloat = 300
        static let detailMinWidth: CGFloat = 180
        static let listMinWidth: CGFloat = 200
        static let pulseDot: CGFloat = 6
        static let rowDot: CGFloat = 6
        /// A hand-off travels its edge in this long; slower than a color change, quicker than a card.
        static let pulseSeconds: TimeInterval = 0.48
        /// One lap of the working arc when the work has no deadline.
        static let sweepSeconds: TimeInterval = 1.2
    }

    // MARK: Motion (DESIGN §5)

    enum Motion {
        static let color = Animation.easeOut(duration: 0.12)
        static let layout = Animation.easeOut(duration: 0.18)
        static let cardIn = Animation.easeOut(duration: 0.24)
        static let cardOut = Animation.easeIn(duration: 0.24)
        static let fade = Animation.easeOut(duration: 0.12)
        static let graphSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)
        static let hoverDelay: Duration = .milliseconds(400)
        static let toast: Duration = .seconds(2)
        static let stopCardHold: Duration = .seconds(2)
        static let pulse: Duration = .milliseconds(480)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif
