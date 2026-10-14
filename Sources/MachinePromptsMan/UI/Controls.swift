#if os(macOS)
import SwiftUI
import MpmHost

/// The controls the landing page draws, so the app and its picture agree. Buttons are pills: a
/// hairline capsule, filled `doing` for the one primary action, `stop` text with a tinted border for
/// the stop, 40% when disabled. Status colors stay strokes and text (DESIGN §3).
struct PillButtonStyle: ButtonStyle {
    enum Kind: Equatable { case plain, primary, stop, toggle(Bool) }
    var kind: Kind = .plain
    var small = false
    /// The key that does the same thing, shown after the title (DESIGN §11 keyboard).
    var key: String? = nil

    func makeBody(configuration: Configuration) -> some View {
        PillBody(kind: kind, small: small, key: key, configuration: configuration)
    }
}

private struct PillBody: View {
    let kind: PillButtonStyle.Kind
    let small: Bool
    let key: String?
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            configuration.label
                .font(small ? Theme.caption : Theme.body)
                .fontWeight(.medium)
                .lineLimit(1)
            if let key {
                Text(key)
                    .font(Theme.keyHint)
                    .opacity(0.7)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, small ? Theme.Space.s12 : Theme.Space.s16)
        .frame(height: small ? Theme.pillButtonSmallHeight : Theme.pillButtonHeight)
        .background(Capsule().fill(fill).brightness(kind == .primary && hovered ? 0.06 : 0))
        .overlay(Capsule().stroke(border, lineWidth: Theme.hairline))
        .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        .contentShape(Capsule())
        .onHover { hovered = $0 }
        .animation(Theme.Motion.color, value: hovered)
    }

    private var foreground: Color {
        switch kind {
        case .plain: return Theme.ink
        case .primary: return Theme.onFill
        case .stop: return Theme.stop
        case .toggle(let on): return on || hovered ? Theme.ink : Theme.ink2
        }
    }

    private var fill: Color { kind == .primary ? Theme.doing : .clear }

    private var border: Color {
        switch kind {
        case .plain: return hovered ? Theme.ink3 : Theme.line
        case .primary: return Theme.doing
        case .stop: return hovered ? Theme.stop : Theme.stop.opacity(0.5)
        case .toggle(let on): return on || hovered ? Theme.ink3 : Theme.line
        }
    }
}

/// A text-only action (the landing page's `.lnk`): `ink2` or an accent, `ink` on hover.
struct LinkButtonStyle: ButtonStyle {
    var color: Color = Theme.ink2
    var font: Font = Theme.caption

    func makeBody(configuration: Configuration) -> some View {
        LinkBody(color: color, font: font, configuration: configuration)
    }
}

private struct LinkBody: View {
    let color: Color
    let font: Font
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(hovered && enabled ? Theme.ink : color)
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(Theme.Motion.color, value: hovered)
    }
}

/// A small caps label in the mono face (the landing page's `.label`): state names, section kickers.
struct Kicker: View {
    let text: String
    var color: Color = Theme.ink2

    init(_ text: String, color: Color = Theme.ink2) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.label)
            .tracking(Theme.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// The mode the system is in, on the right pane's top bar (the landing page's `.modechip`): a dot and
/// the state name in its color, then the one thing it expects next.
struct ModeChip: View {
    let title: String
    let tone: Tone
    var detail: String? = nil

    private var accent: Color { tone == .neutral ? Theme.ink2 : Theme.color(tone) }

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Circle()
                .fill(tone == .neutral ? Theme.ink3 : Theme.color(tone))
                .frame(width: Theme.dotSize, height: Theme.dotSize)
            Kicker(title, color: accent)
            if let detail {
                Text(detail)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.leading, Theme.Space.s8)
        .padding(.trailing, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s4)
        .overlay(Capsule().stroke(Theme.line, lineWidth: Theme.hairline))
        .animation(Theme.Motion.color, value: tone)
        .accessibilityElement(children: .combine)
    }
}

/// Graph / Grid / Monitor (the landing page's `.seg2`): hairline box, the chosen tab on `surface`.
struct SegmentedTabs<T: Hashable>: View {
    @Binding var selection: T
    let items: [(tag: T, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Rectangle().fill(Theme.line).frame(width: Theme.hairline) }
                SegmentButton(title: item.title, selected: selection == item.tag) { selection = item.tag }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: Theme.segmentRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.segmentRadius).stroke(Theme.line, lineWidth: Theme.hairline))
    }
}

private struct SegmentButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.caption)
                .fontWeight(.medium)
                .foregroundStyle(selected || hovered ? Theme.ink : Theme.ink2)
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: Theme.segmentHeight)
                .background(selected ? Theme.surface : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.color, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A count in a hairline capsule (the landing page's `.capsule`): "2 problems", "TEST 60×".
struct CapsuleBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Theme.meta)
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, Theme.Space.s4)
            .overlay(Capsule().stroke(color, lineWidth: Theme.hairline))
    }
}
#endif
