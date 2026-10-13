#if os(macOS)
import SwiftUI
import MpmCore
import MpmHost

/// DESIGN §6 / SPEC §8.6: what the model said, its question, and its proposals as diff rows with
/// Accept / Reject per row and for the whole. Shown only in STRATEGY or with no session; expires at commit.
struct HeldCardView: View {
    let model: AppModel
    @State private var answer = ""
    @State private var message = ""

    private var coordinator: ModelTurnCoordinator { model.coordinator }
    private var store: Store { model.controller.store }

    var body: some View {
        let hasContent = !coordinator.card.isEmpty || store.question != nil || !store.pending.isEmpty
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            if hasContent {
                Text(Strings.fromTheModel).font(Theme.caption).foregroundStyle(Theme.ink2)
                ForEach(coordinator.card) { say in
                    Text(say.text)
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let q = store.question {
                    VStack(alignment: .leading, spacing: Theme.Space.s8) {
                        Text(q.text).font(Theme.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        TextField(Strings.answerPlaceholder, text: $answer)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { send(&answer) }
                    }
                }
                ForEach(store.pending) { p in ProposalCard(model: model, proposal: p) }
            }
            if coordinator.hasModel {
                HStack(spacing: Theme.Space.s8) {
                    TextField(Strings.messagePlaceholder, text: $message)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send(&message) }
                    if coordinator.busy {
                        ProgressView().controlSize(.small).accessibilityLabel(Strings.modelWorking)
                    }
                }
                if coordinator.failure != nil {
                    Text(Strings.modelFailed).font(Theme.caption).foregroundStyle(Theme.stop)
                        .help(coordinator.failure ?? "")
                }
            }
        }
        .padding(hasContent ? Theme.Space.s12 : 0)
        .background {
            if hasContent {
                RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.bg)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.line, lineWidth: Theme.hairline))
            }
        }
        .transition(.opacity)
    }

    private func send(_ text: inout String) {
        coordinator.send(message: text)
        text = ""
    }
}

struct ProposalCard: View {
    let model: AppModel
    let proposal: Proposal

    private static func tmpTitles(_ ops: [Op]) -> [String: String] {
        var tmp: [String: String] = [:]
        for case .addNode(let t, _, let title, _, _, _, _) in ops { tmp[t] = title }
        return tmp
    }

    var body: some View {
        let store = model.controller.store
        let stale = model.coordinator.isStale(proposal)
        let changed = stale ? model.coordinator.changedNodes(since: proposal) : []
        let titles = Self.tmpTitles(proposal.ops)
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            if !proposal.say.isEmpty, !model.coordinator.card.contains(where: { $0.text == proposal.say }) {
                Text(proposal.say).font(Theme.caption).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
            if stale { Text(Strings.stale).font(Theme.caption).foregroundStyle(Theme.blocked) }
            ForEach(Array(proposal.ops.enumerated()), id: \.offset) { i, op in
                let blocked = !OpSummary.existingIDs([op], in: store).filter(changed.contains).isEmpty
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s8) {
                    Text(OpSummary.describe(op, in: store, tmpTitles: titles))
                        .font(Theme.body)
                        .foregroundStyle(blocked ? Theme.ink2 : Theme.ink)
                        .strikethrough(blocked)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.s4)
                    if proposal.ops.count > 1 {
                        Button(Strings.accept) { accept([i]) }
                            .buttonStyle(.borderless)
                            .font(Theme.caption)
                            .disabled(blocked)
                    }
                }
            }
            HStack(spacing: Theme.Space.s8) {
                Button(Strings.acceptAll) { accept(nil) }.buttonStyle(.bordered).disabled(stale)
                Button(Strings.rejectAll) { model.coordinator.reject(proposal.id) }.buttonStyle(.bordered)
                Spacer()
                Button(Strings.lock) {
                    do { try model.coordinator.lock(proposal.id) } catch { model.show(toast: "\(error)") }
                }
                .buttonStyle(.borderless)
                .font(Theme.caption)
                .help(Strings.lockHelp)
            }
        }
        .padding(Theme.Space.s8)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.line, style: StrokeStyle(lineWidth: Theme.hairline, dash: [4, 3])))
    }

    private func accept(_ ops: [Int]?) {
        do { try model.coordinator.accept(proposal.id, ops: ops) } catch { model.show(toast: "\(error)") }
    }
}
#endif
