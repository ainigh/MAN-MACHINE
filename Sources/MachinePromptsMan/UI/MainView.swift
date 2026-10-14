#if os(macOS)
import SwiftUI
import MpmCore
import MpmHost

/// DESIGN §4: a title strip, then the session pane left (fixed 300 pt) and the right pane with its
/// own bar (the mode chip, Graph / Grid / Monitor) above the view. Hairlines between, no shadows.
/// The same picture as the landing page's window.
struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
            HStack(spacing: 0) {
                SessionPaneView(model: model)
                    .frame(width: Theme.sessionPaneWidth)
                    .background(Theme.surface)
                Rectangle().fill(Theme.line).frame(width: Theme.hairline)
                VStack(spacing: 0) {
                    topBar
                    Rectangle().fill(Theme.line).frame(height: Theme.hairline)
                    Group {
                        switch model.rightPane {
                        case .graph: GraphView(model: model)
                        case .grid: GridView(model: model)
                        case .monitor: MonitorView(monitor: model.controller.monitor)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .bottom) {
                    if let t = model.toast {
                        Text(t)
                            .font(Theme.body)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, Theme.Space.s12)
                            .padding(.vertical, Theme.Space.s8)
                            .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                                .stroke(model.toastIsError ? Theme.stop : Theme.line, lineWidth: Theme.hairline))
                            .padding(Theme.Space.s16)
                            .transition(.opacity)
                    }
                }
                .animation(Theme.Motion.fade, value: model.toast)
            }
        }
        .background(Theme.bg)
        .frame(minWidth: Theme.windowMin.width, minHeight: Theme.windowMin.height)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The window's title, drawn by the app so it sits in `ink3` on `surface` like the landing page's
    /// window; the traffic lights stay AppKit's. The window keeps its title for the Window menu.
    private var titlebar: some View {
        ZStack {
            Theme.surface
            Text(Strings.appName)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink3)
        }
        .frame(height: Theme.titlebarHeight)
        .accessibilityHidden(true)
    }

    /// The mode the system is in and the one thing it expects, then the view switch (DESIGN §4, §12).
    private var topBar: some View {
        let state = model.controller.state
        let monitor = model.controller.monitor
        return HStack(spacing: Theme.Space.s8) {
            ModeChip(title: Strings.stateName(state), tone: state.map(Phase.tone) ?? .neutral,
                     detail: Strings.modeHint(state))
            Spacer(minLength: Theme.Space.s8)
            if model.controller.testMode {
                CapsuleBadge(text: Strings.testModeBadge, color: Theme.blocked)
            }
            if model.rightPane != .monitor, monitor.unseenTotal > 0 {
                // A failure elsewhere in the app is visible from any pane, one click from its detail.
                Button { model.rightPane = .monitor } label: {
                    CapsuleBadge(text: Strings.problems(monitor.unseenTotal),
                                 color: monitor.worstUnseen == .error ? Theme.stop : Theme.blocked)
                }
                .buttonStyle(.plain)
            }
            SegmentedTabs(selection: $model.rightPane, items: [
                (tag: RightPane.graph, title: Strings.graph),
                (tag: RightPane.grid, title: Strings.grid),
                (tag: RightPane.monitor, title: Strings.monitor),
            ])
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: Theme.topBarHeight)
    }
}
#endif
