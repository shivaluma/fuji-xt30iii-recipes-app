import SwiftUI

struct SetsListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        List {
            if env.library.sets.isEmpty {
                Text("A Set arranges up to seven recipes for C1–C7 so you can install them later.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(env.library.sets) { set in
                NavigationLink {
                    SetEditorView(setID: set.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(set.name).font(.body.weight(.medium))
                        Text("\(set.filledCount) of 7 slots").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .onDelete { idx in idx.map { env.library.sets[$0].id }.forEach(env.library.deleteSet) }
        }
        .groupedListStyle()
        .navigationTitle("Sets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { name = "My Set"; naming = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Set")
                    .accessibilityIdentifier("newSet")
            }
        }
        .alert("New Set", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") { env.library.createSet(named: name.isEmpty ? "My Set" : name) }
        }
    }
}

struct SetEditorView: View {
    @Environment(AppEnvironment.self) private var env
    var setID: UUID
    @State private var installing = false

    private var set: RecipeSet? { env.library.sets.first { $0.id == setID } }

    var body: some View {
        if let set {
            List {
                Section {
                    ForEach(Array(set.slots.enumerated()), id: \.offset) { index, recipeID in
                        slotRow(set: set, slot: CameraSlot(index: index)!, recipeID: recipeID)
                    }
                    .onMove { from, to in
                        var s = set
                        s.move(fromOffsets: from, toOffset: to)
                        env.library.update(s)
                    }
                } header: {
                    Text("Slots")
                } footer: {
                    Text("Drag to reorder, or use each row's menu. Recipes are linked: editing a recipe updates the Set.")
                }
                Section("Notes") {
                    TextField("Notes", text: Binding(get: { set.notes }, set: { var s = set; s.notes = $0; env.library.update(s) }), axis: .vertical)
                }
                Section {
                    Button("Preview Set in Studio Compare") {
                        env.studio.setCompare(set.slots.compactMap { $0 })
                        env.router.tab = .studio
                    }
                    .disabled(set.filledCount == 0)
                    Button("Install on Camera…") { installing = true }
                        .disabled(set.filledCount == 0)
                        .accessibilityIdentifier("installSet")
                }
            }
            .groupedListStyle()
            .navigationTitle(set.name)
            .inlineNavigationTitle()
            #if os(iOS)
            .toolbar { EditButton() }
            #endif
            .sheet(isPresented: $installing) { SetInstallSheet(set: set) }
        }
    }

    private func slotRow(set: RecipeSet, slot: CameraSlot, recipeID: UUID?) -> some View {
        let recipe = env.library.recipe(recipeID)
        return HStack {
            Text(slot.label).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent).frame(width: 40, alignment: .leading)
            Menu {
                ForEach(env.library.recipes) { r in
                    Button(r.name) { var s = set; s.assign(r.id, to: slot); env.library.update(s) }
                }
                if recipe != nil {
                    Divider()
                    Button("Empty slot", role: .destructive) { var s = set; s.assign(nil, to: slot); env.library.update(s) }
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(recipe?.name ?? (recipeID == nil ? "Empty" : "Missing recipe"))
                        .foregroundStyle(recipe == nil ? Theme.textSecondary : Theme.textPrimary)
                    if let recipe { Text(recipe.filmSimulation.displayName).font(.caption).foregroundStyle(Theme.textSecondary) }
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.label): \(recipe?.name ?? "empty")")
    }
}

/// Installs a Set one slot at a time: per-slot diffs and inclusion, then sequential writes with
/// progress, a safe Stop (finishes the current slot), and per-slot outcomes. Not atomic.
struct SetInstallSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var set: RecipeSet

    @State private var plans: [SlotWritePlan] = []
    @State private var included: Set<CameraSlot> = []
    @State private var preparing = false
    @State private var error: String?
    @State private var acknowledged = false
    @State private var starting = false

    var body: some View {
        let camera = env.camera
        NavigationStack {
            Form {
                if camera.transport == nil {
                    Section { Text("Connect a camera or the demo camera on the Camera tab first. Nothing has been written.") }
                } else {
                    if camera.isDemo {
                        Section { HStack { DemoBadge(); Text("Installing on the in-memory demo camera.").font(.footnote) } }
                    } else {
                        Section { ExperimentalBanner(text: "Experimental. Each slot is written separately; there is no atomic install or automatic rollback.") }
                    }
                    if plans.isEmpty {
                        Section {
                            Button(preparing ? "Reading camera…" : "Review \(set.filledCount) Slot(s)") { Task { await prepare() } }
                                .disabled(preparing)
                        } footer: { Text("FilmLab backs up all slots before reviewing. Nothing is written until you confirm.") }
                    } else {
                        ForEach(plans) { plan in planSection(plan) }
                        Section {
                            if camera.isInstallingSet {
                                Button("Stop After Current Slot", role: .destructive) { camera.requestStop() }
                            } else {
                                Toggle("I understand the included slots will be overwritten one by one.", isOn: $acknowledged)
                                Button(camera.setOutcomes.isEmpty ? "Install" : "Install Remaining (\(remaining.count))", role: .destructive) {
                                    guard !starting else { return } // ignore double taps
                                    starting = true
                                    acknowledged = false
                                    let resuming = !camera.setOutcomes.isEmpty
                                    let slots = Set((resuming ? remaining : plans.filter { included.contains($0.slot) }).map(\.slot))
                                    Task {
                                        // Resuming re-reads and re-diffs: stored "before" values may be stale.
                                        if resuming { await prepare(only: slots) }
                                        await camera.installSet(plans.filter { slots.contains($0.slot) })
                                        starting = false
                                    }
                                }
                                .disabled(starting || !acknowledged || !camera.state.canWrite || included.isEmpty || (!camera.setOutcomes.isEmpty && remaining.isEmpty))
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.danger) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Install “\(set.name)”")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(camera.isInstallingSet) } }
            .interactiveDismissDisabled(camera.isInstallingSet)
            .onAppear { camera.clearSetOutcomes() }
            .onDisappear { camera.clearSetOutcomes() }
            .onChange(of: camera.identity) { _, _ in if !camera.isInstallingSet { plans = []; acknowledged = false } }
        }
    }

    private var remaining: [SlotWritePlan] {
        env.camera.remainingSlots(of: plans.filter { included.contains($0.slot) })
    }

    private func planSection(_ plan: SlotWritePlan) -> some View {
        let outcome = env.camera.setOutcomes[plan.slot]
        return Section {
            Toggle(isOn: Binding(get: { included.contains(plan.slot) }, set: { on in
                if on { included.insert(plan.slot) } else { included.remove(plan.slot) }
            })) {
                VStack(alignment: .leading) {
                    Text("\(plan.slot.label) → \(plan.recipeName)").font(.subheadline.weight(.semibold))
                    Text("Replaces “\(plan.before?.name ?? "?")” · \(plan.changedCount) change(s)").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .disabled(env.camera.isInstallingSet || outcome != nil)
            ForEach(plan.diff.filter { $0.kind == .changed }) { row in
                LabeledContent(row.key.displayName, value: "\(row.before) → \(row.after)").font(.caption)
            }
            if plan.hasBlockingIssues { Text("Has blocking issues; will fail.").font(.caption).foregroundStyle(Theme.danger) }
            if let outcome {
                HStack {
                    if outcome == .writing { ProgressView().controlSize(.small) }
                    Text(outcome.label).font(.caption.weight(.semibold))
                        .foregroundStyle(outcome == .verified ? Theme.authentic : (outcome.isTerminal ? Theme.warning : Theme.textSecondary))
                }
            }
        }
    }

    /// Builds plans (fresh read + diff). `only` limits it to some slots (used when resuming).
    private func prepare(only: Set<CameraSlot>? = nil) async {
        preparing = true
        defer { preparing = false }
        if only == nil { env.camera.clearSetOutcomes() }
        var result: [SlotWritePlan] = only == nil ? [] : plans.filter { !only!.contains($0.slot) }
        for (i, id) in set.slots.enumerated() {
            guard let id, let recipe = env.library.recipe(id), let slot = CameraSlot(index: i) else { continue }
            if let only, !only.contains(slot) { continue }
            do { result.append(try await env.camera.prepareWrite(recipe: recipe, slot: slot)) }
            catch { self.error = error.localizedDescription; return }
        }
        plans = result.sorted { $0.slot < $1.slot }
        if only == nil { included = Set(result.filter { !$0.hasBlockingIssues }.map(\.slot)) }
    }
}
