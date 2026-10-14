#if os(macOS)
import AppKit
import SwiftUI
import MpmCore
import MpmHost

/// View state for the graph: camera, hover, the layout tween, collapse timers, drag. Never store state.
@MainActor
@Observable
final class GraphViewModel {
    var scene = GraphScene()
    var tween = LayoutTween()
    var scale: CGFloat = 1
    var offset: CGPoint = .zero
    var fitted = false
    var hoverPoint: CGPoint?
    var hoverNode: NodeID?
    var tooltip: String?
    var dragNode: NodeID?
    var dragPoint: CGPoint?
    var dropTarget: NodeID?
    var panStart: CGPoint?
    var zoomStart: CGFloat?
    var selectedProposal: String?
    /// Finished subtrees the person opened, and when (DESIGN §8: collapse again after 30 s unselected).
    var expanded: [NodeID: Date] = [:]
    var fade: Double = 1
    var viewSize: CGSize = .zero
    /// Bumped once a layout change has settled, so the frame loop pauses (tasks/10: 0% CPU at rest).
    var settled = 0

    @ObservationIgnored var hoverTask: Task<Void, Never>?
    @ObservationIgnored var collapseTask: Task<Void, Never>?
    @ObservationIgnored var settleTask: Task<Void, Never>?
    @ObservationIgnored var cameraTask: Task<Void, Never>?
    @ObservationIgnored var cameraSaveTask: Task<Void, Never>?
    @ObservationIgnored var scrollMonitor: Any?
    @ObservationIgnored var hovering = false

    static let collapseAfter: TimeInterval = 30
    static let font = NSFont.systemFont(ofSize: Theme.Size.body)
    @ObservationIgnored private var widthCache: [String: Double] = [:]

    func textWidth(_ s: String) -> Double {
        if let w = widthCache[s] { return w }
        let w = Double(ceil((s as NSString).size(withAttributes: [.font: Self.font]).width))
        widthCache[s] = w
        return w
    }

    func toScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y) }
    func toScene(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale) }

    func collapsed(_ store: Store, selection: NodeID?, now: Date) -> Set<NodeID> {
        GraphScene.collapsibleRoots(store).filter { id in
            if let sel = selection, sel == id || store.isDescendant(sel, of: id) { return false }
            if let t = expanded[id], now.timeIntervalSince(t) < Self.collapseAfter { return false }
            return true
        }
    }

    func rebuild(_ store: Store, selection: NodeID?, reduceMotion: Bool) {
        let now = Date()
        let next = GraphScene.make(store, collapsed: collapsed(store, selection: selection, now: now), textWidth: textWidth)
        var targets: [String: CGPoint] = [:]
        var parents: [String: String] = [:]
        for b in next.boxes {
            targets[b.id] = b.center
            if let p = store.nodes[b.id]?.parent { parents[b.id] = p }
        }
        for g in next.ghosts { targets[g.id] = g.center; parents[g.id] = g.parent }
        tween.retarget(targets, parents: parents, now: now, instant: reduceMotion)
        if reduceMotion, scene != next {
            // DESIGN §5: with Reduce Motion, layout changes cross-fade.
            fade = 0.4
            withAnimation(Theme.Motion.layout) { fade = 1 }
        }
        scene = next
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MpmHost.Spring.duration + 0.05))
            guard !Task.isCancelled else { return }
            self?.settled += 1
        }
        scheduleCollapse(store, selection: selection, reduceMotion: reduceMotion)
    }

    private func scheduleCollapse(_ store: Store, selection: NodeID?, reduceMotion: Bool) {
        collapseTask?.cancel()
        let soonest = expanded.values.map { $0.addingTimeInterval(Self.collapseAfter) }.filter { $0 > Date() }.min()
        guard let at = soonest else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, at.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.rebuild(store, selection: selection, reduceMotion: reduceMotion)
        }
    }

    func fit(animated: Bool = false) {
        let (s, o) = GraphScene.fit(scene.bounds, in: viewSize)
        fitted = true
        move(scale: s, offset: o, animated: animated)
    }

    func center(on id: NodeID, animated: Bool) {
        guard let b = scene.box(id), viewSize.width > 0 else { return }
        let target = CGPoint(x: viewSize.width / 2 - b.center.x * scale, y: viewSize.height / 2 - b.center.y * scale)
        move(scale: scale, offset: target, animated: animated)
    }

    /// The canvas does not interpolate `withAnimation`, so the camera eases itself over the layout
    /// duration (DESIGN §5: 180 ms, easeOut). Any pan or zoom by the person takes over at once.
    private func move(scale s1: CGFloat, offset o1: CGPoint, animated: Bool) {
        cameraTask?.cancel()
        guard animated else {
            scale = s1
            offset = o1
            saveCamera()
            return
        }
        let s0 = scale, o0 = offset, start = Date()
        let duration: TimeInterval = 0.18
        cameraTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let t = min(1, Date().timeIntervalSince(start) / duration)
                let e = CGFloat(1 - (1 - t) * (1 - t))
                self.scale = s0 + (s1 - s0) * e
                self.offset = CGPoint(x: o0.x + (o1.x - o0.x) * e, y: o0.y + (o1.y - o0.y) * e)
                if t >= 1 {
                    self.saveCamera()
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func stopCamera() { cameraTask?.cancel() }

    // MARK: Camera memory (DESIGN §11: zoom survives relaunch, and switching to the grid and back)

    private static let cameraKey = "graphCamera"

    func restoreCamera() -> Bool {
        guard let a = UserDefaults.standard.array(forKey: Self.cameraKey) as? [Double], a.count == 3, a[0] > 0 else { return false }
        scale = CGFloat(a[0])
        offset = CGPoint(x: a[1], y: a[2])
        fitted = true
        return true
    }

    func saveCamera() {
        cameraSaveTask?.cancel()
        UserDefaults.standard.set([Double(scale), Double(offset.x), Double(offset.y)], forKey: Self.cameraKey)
    }

    /// Scrolling sends a stream of small moves; write once it rests.
    func saveCameraSoon() {
        cameraSaveTask?.cancel()
        cameraSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveCamera()
        }
    }
}

/// DESIGN §8: the plan as a tidy tree. Pills, edges, dependency arcs, proposal ghosts. Click selects,
/// double-click renames, drag re-parents, right-click for every op, scroll pans, pinch zooms.
struct GraphView: View {
    let model: AppModel
    @State private var vm = GraphViewModel()
    @State private var editText = ""
    @State private var goalText = ""
    @FocusState private var editing: Bool
    @FocusState private var goalFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: Store { model.controller.store }

    /// Changes whenever the drawing would.
    private var sceneKey: String {
        "\(store.version)|\(store.pending.map { "\($0.id):\($0.ops.count)" })|\(model.controller.selection ?? "")|\(vm.expanded.count)"
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: vm.settled >= 0 && !vm.tween.animating(at: Date()))) { ctx in
                // Read here so changes to them redraw the canvas (its closure runs outside body tracking).
                let _ = (vm.scale, vm.offset, vm.dragPoint, vm.dropTarget, vm.selectedProposal, model.dependencySource, vm.scene,
                         model.pickedDoing, model.pickedNext, model.controller.selection, model.canPickSlots)
                Canvas { gc, size in draw(&gc, size: size, now: ctx.date) }
            }
            .opacity(vm.fade)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { doubleClick($0.location) }
                .exclusively(before: SpatialTapGesture(count: 1).onEnded { click($0.location) }))
            .simultaneousGesture(drag)
            .simultaneousGesture(zoom)
            .onContinuousHover { phase in hover(phase) }
            .contextMenu { menuItems(for: vm.hoverNode) }
            .overlay { overlays }
            .onAppear {
                vm.viewSize = geo.size
                vm.rebuild(store, selection: model.controller.selection, reduceMotion: reduceMotion)
                if !vm.fitted, !vm.restoreCamera() { vm.fit() }
                if let f = model.focusRequest { vm.center(on: f, animated: false); model.focusRequest = nil }
                installScrollMonitor()
            }
            .onDisappear {
                removeScrollMonitor()
                vm.saveCamera()
                finishEditing()
            }
            .onChange(of: geo.size) { _, s in vm.viewSize = s }
            .onChange(of: sceneKey) { _, _ in
                vm.rebuild(store, selection: model.controller.selection, reduceMotion: reduceMotion)
            }
            .onChange(of: model.focusRequest) { _, id in
                if let id { vm.center(on: id, animated: !reduceMotion); model.focusRequest = nil }
            }
            .onChange(of: model.editingNode) { _, id in beginEdit(id) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Strings.graph)
            .accessibilityChildren { accessibleNodes }
        }
        .background(Theme.bg)
    }

    // MARK: Drawing

    private func draw(_ gc: inout GraphicsContext, size: CGSize, now: Date) {
        let s = vm.scale
        func pos(_ id: String) -> CGPoint? { vm.tween.position(id, at: now).map(vm.toScreen) }
        func curvePath(_ a: CGPoint, _ b: CGPoint) -> Path {
            var p = Path()
            let from = CGPoint(x: a.x, y: a.y + Theme.pillHeight / 2 * s)
            let to = CGPoint(x: b.x, y: b.y - Theme.pillHeight / 2 * s)
            let midY = (from.y + to.y) / 2
            p.move(to: from)
            p.addCurve(to: to, control1: CGPoint(x: from.x, y: midY), control2: CGPoint(x: to.x, y: midY))
            return p
        }

        // Edges, then dependency arcs, behind the nodes (DESIGN §8).
        for e in vm.scene.edges {
            guard let a = pos(e.parent), let b = pos(e.child) else { continue }
            let ghost = e.child.hasPrefix("ghost:")
            gc.stroke(curvePath(a, b), with: .color(Theme.line),
                      style: StrokeStyle(lineWidth: Theme.hairline, dash: ghost ? [4, 3] : []))
        }
        for d in vm.scene.deps {
            guard let a = pos(d.dep), let b = pos(d.node) else { continue }
            drawDependency(&gc, from: a, to: b, scale: s)
        }
        for m in vm.scene.proposedMoves {
            guard let a = pos(m.parent), let b = pos(m.node) else { continue }
            gc.stroke(curvePath(a, b), with: .color(Theme.next), style: StrokeStyle(lineWidth: Theme.hairline, dash: [4, 3]))
        }

        let doingID = store.doing?.id, nextID = store.next?.id
        let selection = model.controller.selection
        let proposed = Dictionary(vm.scene.proposedStatus.map { ($0.node, $0.status) }, uniquingKeysWith: { a, _ in a })
        for b in vm.scene.boxes {
            guard let c = pos(b.id) else { continue }
            let rect = Self.rect(center: c, size: b.size, scale: s)
            let pill = Path(roundedRect: rect, cornerRadius: Theme.pillRadius * s)
            let isDoing = b.id == doingID
            var layer = gc
            if b.status == .crossedOut { layer.opacity = 0.5 }
            if b.status == .done { layer.opacity = 0.7 }
            layer.fill(pill, with: .color(isDoing ? Theme.doing : Theme.surface))
            if b.id == nextID {
                layer.stroke(pill, with: .color(Theme.next), lineWidth: Theme.statusStroke)
            } else if b.status == .blocked {
                layer.stroke(pill, with: .color(Theme.blocked), style: StrokeStyle(lineWidth: Theme.statusStroke, dash: [4, 3]))
            } else if !isDoing {
                layer.stroke(pill, with: .color(Theme.line), lineWidth: Theme.hairline)
            }
            if let ps = proposed[b.id] {
                // A status change proposal: a second stroke in the proposed color (DESIGN §8).
                let outer = Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: (Theme.pillRadius + 3) * s)
                layer.stroke(outer, with: .color(Theme.color(Tone.of(ps))), style: StrokeStyle(lineWidth: Theme.hairline, dash: [3, 2]))
            }
            if b.id == selection || b.id == vm.dropTarget || b.id == model.dependencySource {
                let ring = Path(roundedRect: rect.insetBy(dx: -5, dy: -5), cornerRadius: (Theme.pillRadius + 5) * s)
                layer.stroke(ring, with: .color(b.id == vm.dropTarget ? Theme.doing : Theme.ink2), lineWidth: Theme.hairline)
            }
            // Status dot: also the D / N picker.
            let dotR = Theme.dotSize / 2 * s
            let dc = CGPoint(x: rect.minX + Theme.pillPadding * s + dotR, y: c.y)
            let dot = Path(ellipseIn: CGRect(x: dc.x - dotR, y: dc.y - dotR, width: dotR * 2, height: dotR * 2))
            layer.fill(dot, with: .color(isDoing ? Theme.onFill : Theme.color(Tone.of(b.status))))
            if model.canPickSlots, b.id == model.pickedDoing || b.id == model.pickedNext {
                let pr = dotR + 3
                let pick = Path(ellipseIn: CGRect(x: dc.x - pr, y: dc.y - pr, width: pr * 2, height: pr * 2))
                layer.stroke(pick, with: .color(b.id == model.pickedDoing ? Theme.doing : Theme.next), lineWidth: Theme.statusStroke)
            }
            var x = dc.x + dotR + 8 * s
            if b.locked {
                let lock = layer.resolve(Image(systemName: "lock.fill"))
                layer.draw(lock, in: CGRect(x: x, y: c.y - Theme.Size.lockGlyph * s / 2, width: Theme.Size.lockGlyph * s, height: Theme.Size.lockGlyph * s))
                x += (Theme.Size.lockGlyph + 4) * s
            }
            var text = Text(b.collapsedCount.map { "\(b.label)  \(Strings.collapsed($0))" } ?? b.label)
                .font(.system(size: Theme.Size.body * s))
                .foregroundColor(isDoing ? Theme.onFill : Theme.ink)
            if b.status == .crossedOut { text = text.strikethrough() }
            layer.draw(text, at: CGPoint(x: x, y: c.y), anchor: .leading)
            if b.status == .done {
                let check = layer.resolve(Text(Image(systemName: "checkmark")).font(.system(size: Theme.Size.checkGlyph * s)).foregroundColor(Theme.done))
                layer.draw(check, at: CGPoint(x: rect.maxX - Theme.pillPadding * s, y: c.y), anchor: .trailing)
            }
        }

        // Proposal ghosts: 50%, dashed (DESIGN §8).
        for g in vm.scene.ghosts {
            guard let c = pos(g.id) else { continue }
            var layer = gc
            layer.opacity = 0.5
            let rect = Self.rect(center: c, size: g.size, scale: s)
            let pill = Path(roundedRect: rect, cornerRadius: Theme.pillRadius * s)
            layer.fill(pill, with: .color(Theme.surface))
            layer.stroke(pill, with: .color(g.proposalID == vm.selectedProposal ? Theme.next : Theme.ink2),
                         style: StrokeStyle(lineWidth: Theme.hairline, dash: [4, 3]))
            layer.draw(Text(g.label).font(.system(size: Theme.Size.body * s)).foregroundColor(Theme.ink),
                       at: CGPoint(x: rect.minX + (Theme.pillPadding + Theme.dotSize + 8) * s, y: c.y), anchor: .leading)
        }

        // The node being dragged follows the pointer.
        if let id = vm.dragNode, let p = vm.dragPoint, let b = vm.scene.box(id) {
            var layer = gc
            layer.opacity = 0.6
            let rect = Self.rect(center: p, size: b.size, scale: s)
            layer.stroke(Path(roundedRect: rect, cornerRadius: Theme.pillRadius * s), with: .color(Theme.doing), lineWidth: Theme.hairline)
            layer.draw(Text(b.label).font(.system(size: Theme.Size.body * s)).foregroundColor(Theme.ink), at: p, anchor: .center)
        }
    }

    static func rect(center c: CGPoint, size: CGSize, scale s: CGFloat) -> CGRect {
        let w: CGFloat = size.width * s
        let h: CGFloat = size.height * s
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    /// A bowed dashed arc from the dependency into the node that waits for it, with a small arrowhead.
    private func drawDependency(_ gc: inout GraphicsContext, from a: CGPoint, to b: CGPoint, scale s: CGFloat) {
        let dx: CGFloat = b.x - a.x
        let dy: CGFloat = b.y - a.y
        let len: CGFloat = max(1, (dx * dx + dy * dy).squareRoot())
        let bow: CGFloat = min(48 * s, len / 4)
        let nx: CGFloat = -dy / len * bow
        let ny: CGFloat = dx / len * bow
        let c1 = CGPoint(x: a.x + dx / 3 + nx, y: a.y + dy / 3 + ny)
        let c2 = CGPoint(x: a.x + 2 * dx / 3 + nx, y: a.y + 2 * dy / 3 + ny)
        var p = Path()
        p.move(to: a)
        p.addCurve(to: b, control1: c1, control2: c2)
        gc.stroke(p, with: .color(Theme.blocked), style: StrokeStyle(lineWidth: Theme.hairline, dash: [4, 3]))

        let tx: CGFloat = b.x - c2.x
        let ty: CGFloat = b.y - c2.y
        let tl: CGFloat = max(1, (tx * tx + ty * ty).squareRoot())
        let ux: CGFloat = tx / tl
        let uy: CGFloat = ty / tl
        let inset: CGFloat = Theme.pillHeight / 2 * s
        let tip = CGPoint(x: b.x - ux * inset, y: b.y - uy * inset)
        let back: CGFloat = 6
        let half: CGFloat = 3
        let left = CGPoint(x: tip.x - ux * back - uy * half, y: tip.y - uy * back + ux * half)
        let right = CGPoint(x: tip.x - ux * back + uy * half, y: tip.y - uy * back - ux * half)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        gc.fill(head, with: .color(Theme.blocked))
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        ZStack(alignment: .topLeading) {
            Button(Strings.fit) { vm.fit(animated: !reduceMotion) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(Theme.Space.s12)
                .padding(.top, Theme.Space.s24)

            if let tip = vm.tooltip, let p = vm.hoverPoint {
                Text(tip)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.s8)
                    .padding(.vertical, Theme.Space.s4)
                    .background(RoundedRectangle(cornerRadius: Theme.cardRadius / 2).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius / 2).stroke(Theme.line, lineWidth: Theme.hairline))
                    .fixedSize()
                    .position(x: p.x + Theme.Space.s16, y: p.y + Theme.Space.s24)
                    .allowsHitTesting(false)
            }

            if let id = model.editingNode, let b = vm.scene.box(id) {
                let c = vm.toScreen(b.center)
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.Size.body * vm.scale))
                    .focused($editing)
                    .frame(width: max(160, b.size.width * vm.scale))
                    .padding(.horizontal, Theme.Space.s8)
                    .padding(.vertical, Theme.Space.s4)
                    .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.pillRadius).stroke(Theme.doing, lineWidth: Theme.hairline))
                    .position(c)
                    .onSubmit { finishEditing() }
                    .onExitCommand { model.editingNode = nil }
            }

            if model.goalNeedsName {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    Text(Strings.nameTheGoal).font(Theme.caption).foregroundStyle(Theme.ink2)
                    TextField(Strings.goalPlaceholder, text: $goalText)
                        .textFieldStyle(.plain)
                        .font(Theme.heading)
                        .focused($goalFocused)
                        .onSubmit { model.nameGoal(goalText) }
                        .onAppear { goalFocused = true }
                }
                .padding(Theme.Space.s24)
                .frame(width: Theme.goalCardWidth)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.line, lineWidth: Theme.hairline))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let pid = vm.selectedProposal, let p = store.pending.first(where: { $0.id == pid }) {
                ProposalCard(model: model, proposal: p)
                    .frame(width: Theme.proposalCardWidth)
                    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
                    .padding(Theme.Space.s16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }

            if model.dependencySource != nil {
                // Esc is handled by the app's key monitor (AppModel.handleKey); a Text cannot take focus.
                Text(Strings.chooseDependency)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.blocked)
                    .padding(Theme.Space.s12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private var accessibleNodes: some View {
        ForEach(vm.scene.boxes) { b in
            Text(b.title)
                .accessibilityLabel(b.title)
                .accessibilityValue(Strings.statusWord(b.status))
                .accessibilityAddTraits(b.id == model.controller.selection ? .isSelected : [])
        }
    }

    // MARK: Interaction

    private func click(_ p: CGPoint) {
        finishEditing()
        let sp = vm.toScene(p)
        if let g = vm.scene.ghostHit(sp) {
            vm.selectedProposal = g.proposalID
            return
        }
        vm.selectedProposal = nil
        let option = NSEvent.modifierFlags.contains(.option)
        if model.canPickSlots, let id = vm.scene.dotHit(sp) {
            if option { model.pick(next: id) } else { model.pick(doing: id) }
            return
        }
        guard let id = vm.scene.hit(sp) else {
            model.controller.selection = nil
            model.dependencySource = nil
            return
        }
        if let src = model.dependencySource {
            model.dependencySource = nil
            if src != id { model.perform([.addDep(id: src, dep: id)]) }
            return
        }
        if let b = vm.scene.box(id), b.collapsedCount != nil {
            vm.expanded[id] = Date()
        }
        if let pid = store.pending.first(where: { $0.ops.contains { $0.touchedIDs.contains(id) } })?.id {
            vm.selectedProposal = pid
        }
        model.controller.selection = id
    }

    private func doubleClick(_ p: CGPoint) {
        finishEditing()
        guard let id = vm.scene.hit(vm.toScene(p)) else { return }
        model.controller.selection = id
        model.editingNode = id
    }

    private func beginEdit(_ id: NodeID?) {
        guard let id, let n = store.nodes[id] else { editing = false; return }
        editText = n.title
        editing = true
    }

    /// Ends inline editing, keeping the text (`rename` ignores blank and unchanged titles). Clicking
    /// elsewhere in the graph keeps what was typed, as a Finder rename does; Esc discards it.
    private func finishEditing() {
        guard let id = model.editingNode else { return }
        model.editingNode = nil
        model.rename(id, to: editText)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                vm.stopCamera()
                if vm.dragNode == nil && vm.panStart == nil {
                    if let id = vm.scene.hit(vm.toScene(v.startLocation)), id != store.rootID, model.controller.state != .break {
                        vm.dragNode = id
                    } else {
                        vm.panStart = vm.offset
                    }
                }
                if vm.dragNode != nil {
                    vm.dragPoint = v.location
                    let over = vm.scene.hit(vm.toScene(v.location))
                    vm.dropTarget = (over == vm.dragNode) ? nil : over
                } else if let start = vm.panStart {
                    vm.offset = CGPoint(x: start.x + v.translation.width, y: start.y + v.translation.height)
                }
            }
            .onEnded { _ in
                if let id = vm.dragNode, let target = vm.dropTarget, store.nodes[id]?.parent != target {
                    model.perform([.moveNode(id: id, parent: target)])
                }
                if vm.panStart != nil { vm.saveCamera() }
                vm.dragNode = nil; vm.dragPoint = nil; vm.dropTarget = nil; vm.panStart = nil
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                vm.stopCamera()
                if vm.zoomStart == nil { vm.zoomStart = vm.scale }
                let anchor = v.startLocation
                let before = vm.toScene(anchor)
                vm.scale = min(3, max(0.2, (vm.zoomStart ?? 1) * v.magnification))
                vm.offset = CGPoint(x: anchor.x - before.x * vm.scale, y: anchor.y - before.y * vm.scale)
            }
            .onEnded { _ in
                vm.zoomStart = nil
                vm.saveCamera()
            }
    }

    private func hover(_ phase: HoverPhase) {
        switch phase {
        case .active(let p):
            vm.hovering = true
            vm.hoverPoint = p
            let sp = vm.toScene(p)
            let node = vm.scene.hit(sp)
            let ghost = vm.scene.ghostHit(sp)
            let key = node ?? ghost?.id
            guard key != vm.hoverNode else { return }
            vm.hoverNode = node
            vm.tooltip = nil
            vm.hoverTask?.cancel()
            guard key != nil else { return }
            // DESIGN §11: full title and freshness after 400 ms.
            let controller = model.controller
            vm.hoverTask = Task { [vm, store] in
                try? await Task.sleep(for: Theme.Motion.hoverDelay)
                guard !Task.isCancelled else { return }
                if let id = node, let n = store.nodes[id] {
                    // Engine time, as the grid's Updated column reads it, so test mode agrees with itself.
                    let days = Int(controller.now().timeIntervalSince(n.updatedAt) / 86_400)
                    vm.tooltip = "\(n.title)  ·  \(Strings.updatedAgo(days))"
                } else if let g = ghost, let p = store.pending.first(where: { $0.id == g.proposalID }) {
                    vm.tooltip = p.say.isEmpty ? g.label : p.say
                }
            }
        case .ended:
            vm.hovering = false
            vm.hoverPoint = nil
            vm.hoverNode = nil
            vm.tooltip = nil
            vm.hoverTask?.cancel()
        }
    }

    /// Scroll to pan (DESIGN §8). SwiftUI has no scroll-wheel event on macOS, so a local monitor
    /// forwards wheel events while the pointer is over the graph.
    private func installScrollMonitor() {
        guard vm.scrollMonitor == nil else { return }
        let line = Self.wheelLine
        vm.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [vm] e in
            // A mouse wheel reports lines, not points; a trackpad reports points.
            let step: CGFloat = e.hasPreciseScrollingDeltas ? 1 : line
            let dx = e.scrollingDeltaX * step, dy = e.scrollingDeltaY * step
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard vm.hovering else { return false }
                vm.stopCamera()
                vm.offset = CGPoint(x: vm.offset.x + dx, y: vm.offset.y + dy)
                vm.saveCameraSoon()
                return true
            }
            return handled ? nil : e
        }
    }

    private static let wheelLine: CGFloat = 16

    private func removeScrollMonitor() {
        if let m = vm.scrollMonitor { NSEvent.removeMonitor(m) }
        vm.scrollMonitor = nil
    }

    // MARK: Context menu (DESIGN §8: statuses, cross out, restore, add child, add dependency, lock)

    @ViewBuilder
    private func menuItems(for id: NodeID?) -> some View {
        if let id, let n = store.nodes[id] {
            let isRoot = id == store.rootID
            Button(Strings.menuRename) { model.controller.selection = id; model.editingNode = id }
            Button(Strings.menuAddChild) { model.addChild(under: id) }
            Divider()
            if !isRoot {
                Button(Strings.menuSetDoing) { model.perform([.setStatus(id, .doing)]) }
                Button(Strings.menuSetNext) { model.perform([.setStatus(id, .next)]) }
                Button(Strings.menuOpen) { model.perform([.setStatus(id, .open)]) }
                Button(Strings.menuDone) { model.perform([.setStatus(id, .done)]) }
                Divider()
                if n.status == .crossedOut {
                    Button(Strings.menuRestore) { model.perform([.restore(id: id)]) }
                } else {
                    Button(Strings.menuCrossOut) { model.perform([.crossOut(id: id)]) }
                }
                Button(Strings.menuAddDependency) { model.dependencySource = id }
                if !n.deps.isEmpty {
                    Menu(Strings.menuRemoveDependency) {
                        ForEach(n.deps, id: \.self) { d in
                            Button(store.nodes[d]?.title ?? d) { model.perform([.removeDep(id: id, dep: d)]) }
                        }
                    }
                }
                Divider()
            }
            Button(n.noSuggest ? Strings.menuUnlock : Strings.menuLock) {
                var f = n.flags
                if n.noSuggest { f.remove(Node.flagNoSuggest) } else { f.insert(Node.flagNoSuggest) }
                model.perform([.updateNode(id: id, fields: NodeFields(flags: f))])
            }
            if model.scheduler.nodeSnoozed(id) {
                Button(Strings.menuResumeNudges) { model.scheduler.snooze(node: id, until: nil) }
            } else {
                Button(Strings.menuSnoozeNudges) {
                    let now = model.controller.now()
                    model.scheduler.snooze(node: id, until: AttentionPolicy.startOfNextDay(after: now, settings: store.settings))
                }
            }
            Button(n.pinned ? Strings.menuUnpin : Strings.menuPin) {
                var f = n.flags
                if n.pinned { f.remove(Node.flagPinned) } else { f.insert(Node.flagPinned) }
                model.perform([.updateNode(id: id, fields: NodeFields(flags: f))])
            }
            if !isRoot, !store.everHeldSlotOrDone(id), store.children(of: id).isEmpty {
                Divider()
                Button(Strings.menuRemove) { model.perform([.removeNode(id: id)]) }
            }
        } else {
            Button(Strings.menuAddChild) { model.addChild(under: store.rootID) }
            Button(Strings.fit) { vm.fit(animated: !reduceMotion) }
        }
    }
}
#endif
