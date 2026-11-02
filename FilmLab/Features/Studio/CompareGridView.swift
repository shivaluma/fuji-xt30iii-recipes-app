import SwiftUI

/// Same photo × 4 or 9 recipes at a consistent crop and exposure. Tap a cell to edit it.
struct CompareGridView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var gridSize = 4

    var body: some View {
        let studio = env.studio
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: gridSize == 9 ? 3 : 2)
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    FidelityBadge(fidelity: .approximateOnDevice)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(studio.compareRecipes.prefix(gridSize)) { r in
                            Button {
                                studio.load(r)
                                dismiss()
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    Group {
                                        if let img = studio.compareResults[r.id]?.image {
                                            CGImageView(image: img, contentMode: .fill)
                                        } else {
                                            Theme.surface.overlay(ProgressView())
                                        }
                                    }
                                    .frame(minHeight: gridSize == 9 ? 110 : 160)
                                    .clipped()
                                    Text(r.name)
                                        .font(.caption2.weight(.semibold)).lineLimit(1)
                                        .padding(6).background(.black.opacity(0.55), in: Capsule())
                                        .padding(6)
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Compare \(r.name). Double-tap to edit.")
                        }
                    }
                    if studio.compareRecipes.isEmpty {
                        Text("Choose recipes to compare.").foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(10)
            }
            .background(Theme.background)
            .navigationTitle("Compare")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Grid", selection: $gridSize) {
                            Text("2 × 2").tag(4)
                            Text("3 × 3").tag(9)
                        }
                        Button("Choose Recipes…") { choosing = true }
                    } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("Grid options")
                }
            }
            .sheet(isPresented: $choosing) { CompareChooser(limit: gridSize) }
            .onAppear { studio.renderCompareGrid() }
        }
    }
}

private struct CompareChooser: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var limit: Int
    @State private var selection: [UUID] = []

    var body: some View {
        let all = env.library.recipes + env.library.catalog.filter { !env.library.isSaved($0.id) }
        NavigationStack {
            List(all) { r in
                Button {
                    if let i = selection.firstIndex(of: r.id) { selection.remove(at: i) }
                    else if selection.count < limit { selection.append(r.id) }
                } label: {
                    HStack {
                        Text(r.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(r.filmSimulation.shortName).font(.caption).foregroundStyle(Theme.textSecondary)
                        Image(systemName: selection.contains(r.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(r.id) ? Theme.accent : Theme.textSecondary)
                    }
                }
            }
            .groupedListStyle()
            .navigationTitle("\(selection.count) of \(limit)")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compare") { env.studio.setCompare(selection); dismiss() }.disabled(selection.isEmpty)
                }
            }
            .onAppear { selection = Array(env.studio.compareRecipeIDs.prefix(limit)) }
        }
    }
}

struct SaveRecipeSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var summary = ""

    var body: some View {
        let studio = env.studio
        let profile = env.settings.myProfile
        let issues = RecipeValidator(profile: profile).validate(studio.recipe.settings)
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Recipe name", text: $name)
                        .accessibilityIdentifier("recipeNameField")
                    TextField("Notes (optional)", text: $summary, axis: .vertical)
                }
                Section("Settings") {
                    ForEach(SlotDiff.rows(before: nil, new: studio.recipe.settings).filter { $0.kind != .keepsCameraValue && $0.kind != .notApplicable }) { row in
                        LabeledContent(row.key.displayName, value: row.after)
                    }
                }
                if !issues.isEmpty {
                    Section("Checks for \(profile.modelName)") {
                        ForEach(issues) { i in
                            Label(i.message, systemImage: i.severity == .error ? "xmark.octagon" : "info.circle")
                                .font(.footnote)
                                .foregroundStyle(i.severity == .error ? Theme.danger : Theme.textSecondary)
                        }
                    }
                }
                Section {
                    Text("Saving stores the recipe in your Library on this iPhone. It does not change your camera.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Save Recipe")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = studio.saveAsNew(name: name.trimmingCharacters(in: .whitespaces), writtenFor: env.settings.myCamera)
                        if !summary.isEmpty { saved.summary = summary; env.library.save(saved) }
                        dismiss()
                    }
                    .accessibilityIdentifier("saveRecipeConfirm")
                }
            }
            .onAppear {
                name = studio.isDirty || !env.library.isSaved(studio.recipe.id) ? "\(studio.recipe.name) Variant" : studio.recipe.name
                summary = studio.recipe.summary
            }
        }
    }
}
