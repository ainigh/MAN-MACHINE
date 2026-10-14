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
                    Picker("", selection: $model.rightPane) {
                        Text(Strings.graph).tag(RightPane.graph)
                        Text(Strings.grid).tag(RightPane.grid)
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
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.stop, lineWidth: Theme.hairline))
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
