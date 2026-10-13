#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MpmCore
import MpmHost

/// tasks/09: everything configurable, in one window, with the derived values live.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            SessionSettings(model: model).tabItem { Text(Strings.tabSession) }
            ModelSettingsView(model: model).tabItem { Text(Strings.tabModel) }
            AttentionSettings(model: model).tabItem { Text(Strings.tabAttention) }
            GeneralSettings(model: model).tabItem { Text(Strings.tabGeneral) }
        }
        .padding(Theme.Space.s16)
        .frame(width: 560, height: 520)
    }
}

// MARK: Session (SPEC §6.1, §11)

private struct SessionSettings: View {
    let model: AppModel
    @State private var R: Double = 10
    @State private var r: Int = 3
    @State private var Ls: Double = 45
    @State private var Lb: Double = 3
    @State private var G: Double = 10

    private var config: SessionConfig { SessionConfig(R: R * 60, r: r, Ls: Ls * 60, Lb: Lb * 60, G: G) }

    var body: some View {
        let readout = ConfigReadout.make(config)
        Form {
            Section {
                minutes(Strings.roundLength, $R)
                Stepper(value: $r, in: 1...8) { LabeledContent(Strings.reminders, value: "\(r)") }
                minutes(Strings.sittingLimit, $Ls, note: Strings.healthNote)
                minutes(Strings.breakLength, $Lb, note: Strings.healthNote)
                LabeledContent(Strings.grace) {
                    TextField("", value: $G, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
                    Text(Strings.seconds).foregroundStyle(Theme.ink2)
                }
                if let e = readout.error {
                    Text(e).font(Theme.caption).foregroundStyle(Theme.stop)
                }
            }
            Section(Strings.derived) {
                LabeledContent(Strings.baseUnit, value: Announcement.fmt(readout.q)).monospacedDigit()
                LabeledContent(Strings.snoozesPerRound, value: "\(readout.zMax)")
                LabeledContent(Strings.reminderTimes) {
                    Text(readout.reminders.joined(separator: ", ") + (readout.merged.map { " (\(Strings.merged($0)))" } ?? ""))
                        .monospacedDigit()
                }
                if readout.error == nil { statusTable(readout) }
            }
            Section {
                HStack {
                    if model.controller.sessionActive {
                        Text(Strings.appliesNextSession).font(Theme.caption).foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    Button(Strings.revert) { load() }
                    Button(Strings.save) { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(readout.error != nil || config == model.controller.store.settings.session)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func minutes(_ label: String, _ value: Binding<Double>, note: String? = nil) -> some View {
        LabeledContent {
            TextField("", value: value, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
            Text(Strings.minutes).foregroundStyle(Theme.ink2)
        } label: {
            Text(label)
            if let note { Text(note).font(Theme.caption).foregroundStyle(Theme.ink2) }
        }
    }

    /// Status length by snoozes used (rows) and nodes cleared (columns): SPEC §6.2.
    private func statusTable(_ r: ConfigReadout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(Strings.statusTable).font(Theme.caption).foregroundStyle(Theme.ink2)
            Grid(alignment: .trailing, horizontalSpacing: Theme.Space.s16, verticalSpacing: Theme.Space.s4) {
                GridRow {
                    Text("z \\ x").foregroundStyle(Theme.ink2)
                    ForEach(Array(ConfigReadout.xColumns), id: \.self) { x in Text("\(x)").foregroundStyle(Theme.ink2) }
                }
                ForEach(Array(r.statusTable.enumerated()), id: \.offset) { z, row in
                    GridRow {
                        Text("\(z)").foregroundStyle(Theme.ink2)
                        ForEach(Array(row.enumerated()), id: \.offset) { _, len in Text(Announcement.fmt(len)) }
                    }
                }
            }
            .font(Theme.captionDigits)
        }
    }

    private func load() {
        let c = model.controller.store.settings.session
        R = c.R / 60; r = c.r; Ls = c.Ls / 60; Lb = c.Lb / 60; G = c.G
    }

    private func save() {
        guard (try? config.validate()) != nil else { return }
        var s = model.controller.store.settings
        s.session = config
        model.controller.updateSettings(s)    // applies at the next start_session (SPEC §11)
    }
}

// MARK: Model (tasks/07)

private struct ModelSettingsView: View {
    let model: AppModel
    @State private var s = ModelSettings()
    @State private var apiKey = ""
    @State private var repair = true

    var body: some View {
        Form {
            Picker(Strings.adapter, selection: $s.kind) {
                Text(Strings.adapterNone).tag(ModelSettings.Kind.none)
                Text(Strings.adapterOllama).tag(ModelSettings.Kind.ollama)
                Text(Strings.adapterAnthropic).tag(ModelSettings.Kind.anthropic)
            }
            switch s.kind {
            case .none:
                EmptyView()
            case .ollama:
                TextField(Strings.endpoint, text: $s.ollamaEndpoint)
                TextField(Strings.modelName, text: $s.ollamaModel)
            case .anthropic:
                TextField(Strings.modelName, text: $s.anthropicModel)
                SecureField(Strings.apiKey, text: $apiKey)
                Text(Strings.apiKeyStored).font(Theme.caption).foregroundStyle(Theme.ink2)
            }
            Toggle(Strings.repairPass, isOn: $repair)
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text(Strings.contextNote)
                TextEditor(text: $s.contextNote).font(Theme.body).frame(height: 80)
                Text(Strings.contextNoteHelp).font(Theme.caption).foregroundStyle(Theme.ink2)
            }
            HStack {
                Spacer()
                Button(Strings.save) {
                    model.applyModelSettings(s, apiKey: apiKey.isEmpty ? nil : apiKey)
                    var core = model.controller.store.settings
                    core.repairPass = repair
                    model.controller.updateSettings(core)
                    apiKey = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            s = model.hostSettings.model
            repair = model.controller.store.settings.repairPass
        }
    }
}

// MARK: Attention (tasks/08)

private struct AttentionSettings: View {
    let model: AppModel
    @State private var start = 22
    @State private var end = 8
    @State private var budget = 6

    var body: some View {
        Form {
            Section(Strings.quietHours) {
                Picker(Strings.from, selection: $start) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker(Strings.to, selection: $end) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Stepper(value: $budget, in: 0...48) { LabeledContent(Strings.maxNudges, value: "\(budget)") }
            }
            RulesAndSnooze(model: model)
            HStack {
                Spacer()
                Button(Strings.save) {
                    var s = model.controller.store.settings
                    s.quietHoursStart = start; s.quietHoursEnd = end; s.maxNudgesPerDay = budget
                    model.controller.updateSettings(s)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let s = model.controller.store.settings
            start = s.quietHoursStart; end = s.quietHoursEnd; budget = s.maxNudgesPerDay
        }
    }
}

/// Shared by the Attention tab and the Schedule window: rules on/off and the attention snooze.
struct RulesAndSnooze: View {
    let model: AppModel

    var body: some View {
        let sch = model.scheduler
        Section(Strings.rulesTitle) {
            ForEach(InitiativeScheduler.ruleNames, id: \.self) { rule in
                Toggle(rule.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                    get: { !sch.settings.disabledRules.contains(rule) },
                    set: { sch.setRule(rule, enabled: $0) }))
            }
        }
        Section(Strings.snoozeSystem) {
            if let until = sch.snoozedUntil {
                Text(Strings.snoozedUntil(until.formatted(date: .abbreviated, time: .shortened))).foregroundStyle(Theme.ink2)
            }
            HStack {
                Button(Strings.snoozeHour) { sch.snooze(until: model.controller.now().addingTimeInterval(3600)) }
                Button(Strings.snoozeTomorrow) {
                    sch.snooze(until: AttentionPolicy.startOfNextDay(after: model.controller.now(), settings: model.controller.store.settings))
                }
                Button(Strings.snoozeNextSession) { sch.snoozeUntilNextSession() }
                if sch.snoozedUntil != nil || sch.settings.snoozedUntilNextSession {
                    Button(Strings.unsnooze) { sch.resume() }
                }
            }
        }
    }
}

// MARK: General

private struct GeneralSettings: View {
    let model: AppModel
    @State private var turnDays = 90
    @State private var systemDays = 30

    var body: some View {
        Form {
            Toggle(Strings.openAtLogin, isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
            Toggle(Strings.sounds, isOn: Binding(get: { !model.muted }, set: { model.muted = !$0 }))
            Toggle(Strings.testMode, isOn: Binding(get: { model.controller.testMode }, set: { model.setTestMode($0) }))
            Section(Strings.retention) {
                Stepper(value: $turnDays, in: 1...3650) { LabeledContent(Strings.turnLogDays, value: "\(turnDays)") }
                Stepper(value: $systemDays, in: 1...3650) { LabeledContent(Strings.systemLogDays, value: "\(systemDays)") }
            }
            HStack {
                Button(Strings.logsFolder) { NSWorkspace.shared.activateFileViewerSelecting([model.persistence.storeURL]) }
                Button(Strings.exportStore, action: export)
                Spacer()
                Button(Strings.save) {
                    model.scheduler.update { $0.turnLogDays = turnDays; $0.systemLogDays = systemDays }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            turnDays = model.hostSettings.turnLogDays
            systemDays = model.hostSettings.systemLogDays
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "machine-prompts-man-store.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.persistence.export(model.controller.store, to: url) } catch { model.show(toast: "\(error)") }
    }
}

// MARK: Schedule window (tasks/08) and transcript sheet (tasks/04)

struct ScheduleView: View {
    let model: AppModel

    var body: some View {
        let entries = model.controller.store.schedule.sorted { $0.at < $1.at }
        Form {
            Section(Strings.upcoming) {
                if entries.isEmpty {
                    Text(Strings.nothingScheduled).foregroundStyle(Theme.ink2)
                }
                ForEach(entries) { e in
                    HStack {
                        Text(e.at.formatted(date: .abbreviated, time: .shortened)).monospacedDigit()
                        Text(e.reason).foregroundStyle(Theme.ink2).lineLimit(1)
                        Spacer()
                        Text(e.source.rawValue).font(Theme.caption).foregroundStyle(Theme.ink2)
                        Button { model.scheduler.removeSchedule(e.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            RulesAndSnooze(model: model)
            if let d = model.scheduler.lastDecision {
                Text(d).font(Theme.caption).foregroundStyle(Theme.ink2)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
    }
}

struct TranscriptView: View {
    let controller: SessionController

    var body: some View {
        let start = controller.store.session?.startedAt ?? controller.announcements.first?.at ?? Date()
        List(controller.announcements.reversed()) { a in
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s12) {
                Text(Announcement.fmt(max(0, a.at.timeIntervalSince(start))))
                    .font(Theme.captionDigits)
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 60, alignment: .trailing)
                Text(a.text).font(Theme.body).textSelection(.enabled)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
#endif
