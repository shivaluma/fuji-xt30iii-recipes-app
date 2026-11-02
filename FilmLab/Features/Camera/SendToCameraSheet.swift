import SwiftUI

/// Single-slot write: choose slot → fresh read + backup → per-setting diff → explicit
/// confirmation → guarded write → read-back verification → result.
struct SendToCameraSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var recipeID: UUID

    enum Step: Equatable {
        case chooseSlot
        case preparing
        case review
        case writing
        case done(SlotWriteOutcome)
        case error(String)
    }

    @State private var step: Step = .chooseSlot
    @State private var slot: CameraSlot = .c7
    @State private var slotName = ""
    @State private var plan: SlotWritePlan?
    @State private var acknowledged = false

    var body: some View {
        let recipe = env.library.recipe(recipeID)
        NavigationStack {
            Form {
                if let recipe {
                    Section { LabeledContent("Recipe", value: recipe.name) }
                    if env.camera.transport == nil {
                        Section {
                            Text("Connect a camera (or the demo camera) on the Camera tab first. Nothing has been written.")
                            Button("Use Demo Camera") { Task { await env.camera.connectDemo() } }
                        }
                    } else {
                        content(recipe)
                    }
                }
            }
            .formPage()
            .navigationTitle("Send to Camera")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Cancel") { dismiss() }.disabled(step == .writing)
                }
            }
            .interactiveDismissDisabled(step == .writing)
            .onAppear { if let r = recipe { slotName = FujiRecipeCodec.suggestedSlotName(for: r.name) } }
            .onChange(of: env.camera.identity) { _, _ in
                // A review belongs to one connection; start over if the camera changes.
                if step != .writing, !isFinished { plan = nil; acknowledged = false; step = .chooseSlot }
            }
        }
    }

    private var isFinished: Bool { if case .done = step { return true } else { return false } }

    @ViewBuilder private func content(_ recipe: FilmRecipe) -> some View {
        if env.camera.isDemo {
            Section { HStack { DemoBadge(); Text("Writing to the in-memory demo camera.").font(.footnote) } }
        } else {
            Section { ExperimentalBanner(text: "Experimental: unofficial protocol, not verified on a physical X-T30 III. Writes are not atomic and cannot be rolled back automatically.") }
        }
        switch step {
        case .chooseSlot:
            Section {
                DestinationCard(
                    slot: slot,
                    title: env.camera.snapshots[slot]?.name ?? "Not read yet",
                    subtitle: env.camera.snapshots[slot]?.settings?.filmSimulation.displayName ?? "Current contents are read before review",
                    ctaTitle: "Review Changes for \(slot.label)",
                    ctaIcon: "list.bullet.rectangle",
                    ctaIdentifier: "reviewChanges",
                    picker: {
                        ForEach(CameraSlot.allCases) { s in
                            Button("\(s.label) · \(env.camera.snapshots[s]?.name ?? "not read")") { slot = s }
                        }
                    },
                    action: { Task { await prepare(recipe) } })
            } footer: {
                Text("FilmLab reads \(slot.label) and backs up all seven slots first. Nothing is written until you confirm.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            Section("Name on camera") {
                TextField("Slot name", text: $slotName)
                Text("Up to \(FujiRecipeCodec.slotNameMaxLength) characters: letters, digits, spaces, basic punctuation (limit reported by community notes).")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        case .preparing:
            Section { HStack { ProgressView(); Text("Reading \(slot.label) and backing up…") } }
        case .review:
            if let plan { review(plan) }
        case .writing:
            Section { HStack { ProgressView(); Text("Writing \(slot.label)… Don't disconnect the camera.") } }
        case .done(let outcome):
            result(outcome)
        case .error(let m):
            Section {
                Label(m, systemImage: "xmark.octagon").foregroundStyle(Theme.danger)
                Text("Nothing was written.").font(.footnote)
                Button("Back") { step = .chooseSlot }
            }
        }
    }

    @ViewBuilder private func review(_ plan: SlotWritePlan) -> some View {
        Section("\(plan.slot.label): “\(plan.before?.name ?? "?")” → “\(plan.slotName)”") {
            ForEach(plan.diff) { row in
                HStack {
                    Text(row.key.displayName).font(.footnote)
                    Spacer()
                    switch row.kind {
                    case .changed:
                        Text(row.before).font(.footnote).foregroundStyle(Theme.textSecondary).strikethrough()
                        Image(systemName: "arrow.right").font(.caption2)
                        Text(row.after).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    case .unchanged:
                        Text(row.after).font(.footnote).foregroundStyle(Theme.textSecondary)
                    case .keepsCameraValue:
                        Text("keeps \(row.before)").font(.footnote).foregroundStyle(Theme.textSecondary).italic()
                    case .notApplicable:
                        Text("n/a").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        if !plan.issues.isEmpty {
            Section("Checks") {
                ForEach(plan.issues) { i in
                    Label(i.message, systemImage: i.severity == .error ? "xmark.octagon" : "info.circle")
                        .font(.footnote).foregroundStyle(i.severity == .error ? Theme.danger : Theme.textSecondary)
                }
            }
        }
        Section {
            Toggle("I understand this overwrites \(plan.slot.label). A backup was saved.", isOn: $acknowledged)
                .tint(Theme.accent)
                .accessibilityIdentifier("acknowledgeOverwrite")
            if !env.camera.state.canWrite {
                Text("Writes are disabled for this connection. Enable experimental slot writes in Settings.").font(.footnote).foregroundStyle(Theme.warning)
            }
        }
        Section {
            DestinationCard(
                slot: plan.slot,
                title: plan.slotName,
                subtitle: "\(plan.settings.filmSimulation.displayName) · replaces “\(plan.before?.name ?? "?")”",
                ctaTitle: "Write to \(plan.slot.label)",
                ctaEnabled: acknowledged && !plan.hasBlockingIssues && env.camera.state.canWrite,
                ctaIdentifier: "confirmWrite",
                picker: {
                    Button("Choose a different slot") { self.plan = nil; acknowledged = false; step = .chooseSlot }
                },
                action: {
                    guard step == .review else { return } // ignore double taps
                    step = .writing
                    acknowledged = false
                    Task { step = .done(await env.camera.execute(plan)) }
                })
        } footer: {
            Text("\(plan.changedCount) setting(s) will change. Settings marked “keeps” are not in the recipe and stay as they are. Properties FilmLab doesn't understand are never written.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private func result(_ outcome: SlotWriteOutcome) -> some View {
        Section {
            switch outcome {
            case .verified:
                Label("\(slot.label) written and verified by read-back.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.authentic)
                Text("Set the film simulation dial to C and choose \(slot.label) in SELECT CUSTOM SETTING to use it. The AUTO lever and movie mode use different settings.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            case .mismatched(let rows):
                Label("Written, but read-back differs:", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                ForEach(rows, id: \.self) { Text($0).font(.caption.monospaced()) }
                Text("Your backup is on the Camera tab.").font(.footnote)
            case .unknown(let m):
                Label("Outcome unknown", systemImage: "questionmark.diamond").foregroundStyle(Theme.warning)
                Text(m).font(.footnote)
                Text("Reconnect and read \(slot.label) before assuming anything. FilmLab has not rolled anything back.").font(.footnote)
            case .failed(let m):
                Label("Write failed", systemImage: "xmark.octagon").foregroundStyle(Theme.danger)
                Text(m).font(.footnote)
            default:
                Text(outcome.label)
            }
        }
        .accessibilityIdentifier("writeResult")
    }

    private func prepare(_ recipe: FilmRecipe) async {
        step = .preparing
        acknowledged = false
        do {
            plan = try await env.camera.prepareWrite(recipe: recipe, slot: slot, slotName: slotName)
            step = .review
        } catch {
            step = .error(error.localizedDescription)
        }
    }
}
