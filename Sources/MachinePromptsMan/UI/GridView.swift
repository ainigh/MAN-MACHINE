#if os(macOS)
import AppKit
import SwiftUI
import MpmCore
import MpmHost

struct GridRowItem: Identifiable, Equatable {
    let id: NodeID
    let node: Node
    let depth: Int
}

/// DESIGN §9: the working surface. Tree order with indentation, inline edit on every cell except
/// updated, quick-log at the bottom. Every edit is a Man patch through the controller; a refused edit
/// reverts the cell and shows the reason (tasks/06).
struct GridView: View {
    let model: AppModel
    @State private var quickLog = ""
    @FocusState private var quickLogFocused: Bool

    private var store: Store { model.controller.store }

    var body: some View {
        let rows = TreeOrder.rows(store).map { GridRowItem(id: $0.node.id, node: $0.node, depth: $0.depth) }
        VStack(spacing: 0) {
            Table(rows, selection: selection) {
                TableColumn(Strings.columnTitle) { r in TitleCell(model: model, row: r) }
                TableColumn(Strings.columnStatus) { r in StatusCell(model: model, node: r.node, isRoot: r.id == store.rootID) }
                    .width(min: 90, ideal: 110)
                TableColumn(Strings.columnDue) { r in DueCell(model: model, node: r.node) }
                    .width(min: 110, ideal: 130)
                TableColumn(Strings.columnProgress) { r in ProgressCell(model: model, node: r.node) }
                    .width(min: 80, ideal: 100)
                TableColumn(Strings.columnLinks) { r in LinksCell(model: model, node: r.node) }
                    .width(min: 44, ideal: 56)
                TableColumn(Strings.columnUpdated) { r in
                    Text(Strings.updatedAgo(Int(model.controller.now().timeIntervalSince(r.node.updatedAt) / 86_400)))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.ink2)
                }
                .width(min: 80, ideal: 100)
            }
            .padding(.top, Theme.Space.s32)
            Rectangle().fill(Theme.line).frame(height: Theme.hairline)
            TextField(Strings.quickLogPlaceholder, text: $quickLog)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .focused($quickLogFocused)
                .padding(Theme.Space.s12)
                .onSubmit(addFromQuickLog)
        }
        .background(Theme.bg)
    }

    private var selection: Binding<NodeID?> {
        Binding(get: { model.controller.selection }, set: { id in
            model.controller.selection = id
            model.focusRequest = id                 // the graph pans here when it is shown (tasks/06)
        })
    }

    /// Enter adds a node under the selection (or the root) and keeps the field focused for the next one.
    private func addFromQuickLog() {
        let t = quickLog.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let parent = model.controller.selection ?? store.rootID
        if model.perform([.add(t, under: parent, tmp: "q")]) != nil { quickLog = "" }
        quickLogFocused = true
    }
}

private struct TitleCell: View {
    let model: AppModel
    let row: GridRowItem
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s4) {
            Spacer().frame(width: CGFloat(row.depth) * Theme.Space.s16)
            if row.node.noSuggest {
                Image(systemName: "lock.fill").font(.system(size: Theme.Size.lockGlyph)).foregroundStyle(Theme.ink2)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.body)
                .strikethrough(row.node.status == .crossedOut)
                .foregroundStyle(row.node.status.isFinished ? Theme.ink2 : Theme.ink)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { text = row.node.title; focused = false }
        }
        // Tabbing or clicking out of a cell keeps the edit, as Return does; Esc puts the title back.
        .onChange(of: focused) { was, now in if was && !now { commit() } }
        .onAppear { text = row.node.title }
        .onChange(of: row.node.title) { _, t in text = t }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != row.node.title else { return }
        if t.isEmpty || model.perform([.updateNode(id: row.id, fields: NodeFields(title: t))]) == nil {
            text = row.node.title                   // refused: revert the cell
        }
    }
}

private struct StatusCell: View {
    let model: AppModel
    let node: Node
    let isRoot: Bool

    var body: some View {
        Menu {
            ForEach([Status.open, .doing, .next, .done], id: \.self) { s in
                Button(Strings.statusWord(s)) { model.perform([.setStatus(node.id, s)]) }
            }
            Divider()
            if node.status == .crossedOut {
                Button(Strings.menuRestore) { model.perform([.restore(id: node.id)]) }
            } else {
                Button(Strings.menuCrossOut) { model.perform([.crossOut(id: node.id)]) }
            }
        } label: {
            Text(Strings.statusWord(node.status))
                .font(Theme.caption)
                .foregroundStyle(Theme.color(Tone.of(node.status)))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRoot)
    }
}

private struct DueCell: View {
    let model: AppModel
    let node: Node

    var body: some View {
        HStack(spacing: Theme.Space.s4) {
            if let due = node.due {
                DatePicker("", selection: Binding(get: { due }, set: { d in
                    model.perform([.updateNode(id: node.id, fields: NodeFields(due: d))])
                }), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                Button(Strings.clearDue) { model.perform([.updateNode(id: node.id, fields: NodeFields(clearDue: true))]) }
                    .buttonStyle(.borderless)
                    .font(Theme.caption)
            } else {
                Button(Strings.noDue) {
                    // Engine time, so test mode's 60× timeline agrees with the Updated column.
                    let today = Calendar.current.startOfDay(for: model.controller.now())
                    model.perform([.updateNode(id: node.id, fields: NodeFields(due: today))])
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.ink2)
            }
        }
    }
}

private struct ProgressCell: View {
    let model: AppModel
    let node: Node
    @State private var editing = false
    @State private var value: Double = 0

    var body: some View {
        Button { value = Double(node.progress); editing = true } label: {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line)
                    Rectangle().fill(Theme.done).frame(width: geo.size.width * CGFloat(node.progress) / 100)
                }
                .frame(height: Theme.statusStroke)
                .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(node.progress)%")
        .popover(isPresented: $editing) {
            HStack(spacing: Theme.Space.s8) {
                Slider(value: $value, in: 0...100, step: 5) { started in
                    if !started { model.perform([.updateNode(id: node.id, fields: NodeFields(progress: Int(value)))]) }
                }
                .frame(width: 160)
                Text("\(Int(value))%").font(Theme.digits).frame(width: 40, alignment: .trailing)
            }
            .padding(Theme.Space.s12)
        }
    }
}

private struct LinksCell: View {
    let model: AppModel
    let node: Node
    @State private var open = false
    @State private var newLink = ""

    var body: some View {
        Button("\(node.links.count)") { open = true }
            .buttonStyle(.borderless)
            .font(Theme.digits)
            .foregroundStyle(node.links.isEmpty ? Theme.ink2 : Theme.ink)
            .popover(isPresented: $open) {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    ForEach(node.links, id: \.self) { link in
                        HStack(spacing: Theme.Space.s8) {
                            Button(link) { if let u = URL(string: link) { NSWorkspace.shared.open(u) } }
                                .buttonStyle(.link)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(link)
                            Spacer()
                            Button { set(node.links.filter { $0 != link }) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    TextField(Strings.linkPlaceholder, text: $newLink)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let l = newLink.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !l.isEmpty else { return }
                            set(node.links + [l]); newLink = ""
                        }
                }
                .padding(Theme.Space.s12)
                .frame(width: 320)
            }
    }

    private func set(_ links: [String]) {
        model.perform([.updateNode(id: node.id, fields: NodeFields(links: links))])
    }
}
#endif
