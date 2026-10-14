#if os(macOS)
import SwiftUI
import MpmCore
import MpmHost

/// DESIGN §4: session pane left (fixed 300 pt), graph or grid right, hairlines between, no shadows.
struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SessionPaneView(model: model)
                .frame(width: Theme.sessionPaneWidth)
                .background(Theme.surface)
            Rectangle().fill(Theme.line).frame(width: Theme.hairline)
            ZStack(alignment: .topTrailing) {
                Group {
                    switch model.rightPane {
                    case .graph: GraphView(model: model)
                    case .grid: GridView(model: model)
                    case .monitor: MonitorView(monitor: model.controller.monitor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: Theme.Space.s8) {
                    if model.controller.testMode {
                        Text(Strings.testModeBadge)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.blocked)
                            .padding(.horizontal, Theme.Space.s8)
                            .padding(.vertical, Theme.Space.s4)
                            .overlay(Capsule().stroke(Theme.blocked, lineWidth: Theme.hairline))
                    }
                    let monitor = model.controller.monitor
                    if model.rightPane != .monitor, monitor.unseenTotal > 0 {
                        // A failure elsewhere in the app is visible from any pane, one click from its detail.
                        Button(Strings.problems(monitor.unseenTotal)) { model.rightPane = .monitor }
                            .buttonStyle(.plain)
                            .font(Theme.caption)
                            .foregroundStyle(monitor.worstUnseen == .error ? Theme.stop : Theme.blocked)
                            .padding(.horizontal, Theme.Space.s8)
                            .padding(.vertical, Theme.Space.s4)
                            .overlay(Capsule().stroke(monitor.worstUnseen == .error ? Theme.stop : Theme.blocked,
                                                      lineWidth: Theme.hairline))
                    }
                    Picker("", selection: $model.rightPane) {
                        Text(Strings.graph).tag(RightPane.graph)
                        Text(Strings.grid).tag(RightPane.grid)
                        Text(Strings.monitor).tag(RightPane.monitor)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(Theme.Space.s12)
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
        .background(Theme.bg)
        .frame(minWidth: Theme.windowMin.width, minHeight: Theme.windowMin.height)
        .ignoresSafeArea(.container, edges: .top)
    }
}
#endif
