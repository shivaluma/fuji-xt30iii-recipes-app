import SwiftUI

/// A shooting situation used for quick browsing. Matching uses FilmLab's own tags and moods.
struct Situation: Identifiable, Hashable {
    var id: String
    var emoji: String
    var title: String
    var tags: Set<String>
    var moods: Set<RecipeMood>

    func matches(_ r: FilmRecipe) -> Bool {
        !tags.isDisjoint(with: r.tags) || !moods.isDisjoint(with: r.moods)
    }

    static let all: [Situation] = [
        .init(id: "sun", emoji: "☀️", title: "Bright Sun", tags: ["landscape", "travel", "nature", "sunset"], moods: [.vivid]),
        .init(id: "portrait", emoji: "👤", title: "Portraits", tags: ["portrait"], moods: []),
        .init(id: "overcast", emoji: "☁️", title: "Overcast", tags: ["overcast"], moods: [.muted]),
        .init(id: "street", emoji: "🚶", title: "Street", tags: ["street", "urban", "architecture"], moods: []),
        .init(id: "night", emoji: "🌙", title: "Night", tags: ["night"], moods: [.cinematic]),
        .init(id: "indoor", emoji: "🪟", title: "Indoors", tags: ["interior", "food"], moods: []),
        .init(id: "bw", emoji: "🖤", title: "B&W", tags: ["bw"], moods: [.blackAndWhite]),
    ]
}

/// Searchable local catalog (FilmLab originals + your library). No web scraping.
struct ExploreView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var searching = false
    @State private var situation: Situation?
    @State private var moods: Set<RecipeMood> = []
    @State private var simulation: FilmSimulation?
    @State private var showFilters = false
    @State private var showImport = false
    @FocusState private var searchFocused: Bool

    private var pool: [FilmRecipe] {
        let library = env.library
        return library.catalog + library.recipes.filter { r in !library.catalog.contains { $0.id == r.id } }
    }

    private var isFiltering: Bool { !query.isEmpty || situation != nil || !moods.isEmpty || simulation != nil }

    private var results: [FilmRecipe] {
        pool.filter { r in
            (query.isEmpty || r.name.localizedCaseInsensitiveContains(query) || r.summary.localizedCaseInsensitiveContains(query)
                || r.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                || r.filmSimulation.displayName.localizedCaseInsensitiveContains(query))
            && (situation?.matches(r) ?? true)
            && (moods.isEmpty || !moods.isDisjoint(with: r.moods))
            && (simulation == nil || r.filmSimulation == simulation)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeader(title: "Explore") {
                        CircleIconButton(systemName: "magnifyingglass", accessibilityLabel: "Search") {
                            withAnimation(.snappy) { searching.toggle() }
                            searchFocused = searching
                            if !searching { query = "" }
                        }
                        CircleIconButton(systemName: "line.3.horizontal.decrease", tint: moods.isEmpty && simulation == nil ? Theme.textPrimary : Theme.accent,
                                         accessibilityLabel: "Filters") { showFilters = true }
                        Menu {
                            Button("New Recipe", systemImage: "plus") {
                                env.studio.load(FilmRecipe(name: "New Recipe", settings: .neutral()))
                                env.router.tab = .studio
                            }
                            Button("Import from Image or Text…", systemImage: "text.viewfinder") { showImport = true }
                        } label: {
                            CircleIconLabel(systemName: "plus", tint: Theme.accent)
                        }
                        .accessibilityLabel("Add recipe")
                        .accessibilityIdentifier("exploreAdd")
                    }
                    if searching { searchField }
                    situations
                    if isFiltering {
                        resultsGrid
                    } else {
                        carousel(title: "FilmLab Originals", subtitle: "Starter looks made for this app",
                                 recipes: env.library.catalog.filter { !$0.filmSimulation.isMonochrome })
                        let mine = env.library.recipes.filter { $0.provenance.kind != .filmLabOriginal }
                        if !mine.isEmpty {
                            carousel(title: "Your Recipes", subtitle: "Saved on this iPhone", recipes: mine)
                        }
                        carousel(title: "Black & White", subtitle: "Monochrome starters",
                                 recipes: pool.filter { $0.filmSimulation.isMonochrome })
                    }
                    Text("Starter recipes are original FilmLab creations. Thumbnails are approximate on-device previews on a synthetic test image.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.gutter)
                }
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .hiddenNavigationBar()
            .navigationDestination(for: UUID.self) { id in RecipeDetailView(recipeID: id) }
            .navigationDestination(for: RecipeListRoute.self) { route in
                RecipeGridScreen(title: route.title, recipes: route.ids.compactMap { env.library.recipe($0) })
            }
            .sheet(isPresented: $showFilters) { filterSheet }
            .sheet(isPresented: $showImport) { RecipeImportView() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Recipes, simulations, tags", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, Theme.gutter)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var situations: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Browse by Situation", subtitle: "Pick a look for what you're shooting")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Situation.all) { s in
                        PillChip(emoji: s.emoji, title: s.title, selected: situation == s) {
                            withAnimation(.snappy) { situation = situation == s ? nil : s }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private func carousel(title: String, subtitle: String, recipes: [FilmRecipe]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: RecipeListRoute(title: title, ids: recipes.map(\.id))) {
                SectionHeader(title: title, subtitle: subtitle, actionTitle: "See all", action: {})
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(recipes) { r in
                        NavigationLink(value: r.id) {
                            PhotoRecipeCard(recipe: r, thumbnail: env.thumbnails.thumbnail(for: r), width: 250, saved: env.library.isSaved(r.id))
                                .onAppear { env.thumbnails.request(r) }
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "\(results.count) recipe\(results.count == 1 ? "" : "s")",
                          subtitle: situation.map { "\($0.emoji) \($0.title)" },
                          actionTitle: "Clear", action: { query = ""; situation = nil; moods = []; simulation = nil })
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                RecipeGrid(recipes: results)
            }
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("MOOD").font(Theme.Font.eyebrow).tracking(1.2).foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(RecipeMood.allCases, id: \.self) { m in
                            FilterChip(title: m.displayName, isOn: moods.contains(m)) {
                                if moods.contains(m) { moods.remove(m) } else { moods.insert(m) }
                            }
                        }
                    }
                    Text("FILM SIMULATION").font(Theme.Font.eyebrow).tracking(1.2).foregroundStyle(Theme.textSecondary)
                    FlowLayout(spacing: 8) {
                        FilterChip(title: "Any", isOn: simulation == nil) { simulation = nil }
                        ForEach(FilmSimulation.allCases) { sim in
                            FilterChip(title: sim.shortName, isOn: simulation == sim) { simulation = sim }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.background)
            .navigationTitle("Filters")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { moods = []; simulation = nil } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showFilters = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct RecipeListRoute: Hashable {
    var title: String
    var ids: [UUID]
}

/// Two-column grid of large photo cards.
struct RecipeGrid: View {
    @Environment(AppEnvironment.self) private var env
    var recipes: [FilmRecipe]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
            ForEach(recipes) { r in
                NavigationLink(value: r.id) {
                    PhotoRecipeCard(recipe: r, thumbnail: env.thumbnails.thumbnail(for: r), width: nil, saved: env.library.isSaved(r.id))
                        .onAppear { env.thumbnails.request(r) }
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

struct RecipeGridScreen: View {
    var title: String
    var recipes: [FilmRecipe]
    var body: some View {
        ScrollView {
            RecipeGrid(recipes: recipes).padding(.top, 12).padding(.bottom, 110)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .inlineNavigationTitle()
    }
}

/// Settings, provenance and actions for one recipe.
struct RecipeDetailView: View {
    @Environment(AppEnvironment.self) private var env
    var recipeID: UUID
    @State private var renaming = false
    @State private var newName = ""
    @State private var publishing = false
    @State private var publishResult: String?

    var body: some View {
        if let r = env.library.recipe(recipeID) {
            content(r)
        } else {
            ContentUnavailableView("Recipe not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func content(_ r: FilmRecipe) -> some View {
        let saved = env.library.isSaved(r.id)
        let issues = RecipeValidator(profile: .xt30III).validate(r.settings)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if let t = env.thumbnails.thumbnail(for: r) { CGImageView(image: t, contentMode: .fill) } else { Theme.swatch(for: r.filmSimulation) }
                    }
                    .frame(height: 200).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) { FidelityBadge(fidelity: .approximateOnDevice).padding(8) }
                    .onAppear { env.thumbnails.request(r) }
                    if !r.summary.isEmpty { Text(r.summary).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                Button { tryInStudio(r) } label: { Label("Try in Studio", systemImage: "camera.filters") }
                    .accessibilityIdentifier("tryInStudio")
                if saved {
                    Button { env.library.toggleFavorite(r.id) } label: {
                        Label(r.isFavorite ? "Remove Favorite" : "Favorite", systemImage: r.isFavorite ? "heart.slash" : "heart")
                    }
                    Button { env.library.duplicate(r) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    if r.provenance.kind != .filmLabOriginal {
                        Button { newName = r.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    }
                    Button {
                        env.router.pendingSendRecipeID = r.id
                        env.router.tab = .camera
                    } label: { Label("Send to Camera…", systemImage: "camera") }
                    if let client = env.settings.webClient {
                        Button {
                            publishing = true
                            Task {
                                defer { publishing = false }
                                do { publishResult = "Published: " + (try await client.publish(r, published: true, story: nil)).absoluteString }
                                catch { publishResult = error.localizedDescription }
                            }
                        } label: { Label(publishing ? "Publishing…" : "Publish to Web", systemImage: "globe") }
                        .disabled(publishing)
                        if let publishResult { Text(publishResult).font(.footnote).foregroundStyle(Theme.textSecondary).textSelection(.enabled) }
                    }
                } else {
                    Button { env.library.saveToLibrary(r) } label: { Label("Save to Library", systemImage: "tray.and.arrow.down") }
                        .accessibilityIdentifier("saveToLibrary")
                }
            }
            Section("Settings") {
                ForEach(SlotDiff.rows(before: nil, new: r.settings)) { row in
                    LabeledContent(row.key.displayName, value: row.kind == .keepsCameraValue ? "Not set" : row.after)
                        .foregroundStyle(row.kind == .notApplicable || row.kind == .keepsCameraValue ? Theme.textSecondary : Theme.textPrimary)
                }
                if let ev = r.settings.suggestedExposureCompensation.concreteValue {
                    LabeledContent("Suggested exposure", value: (ev > 0 ? "+" : "") + String(format: "%.1f EV", ev))
                }
            }
            if !issues.isEmpty {
                Section("Compatibility · \(CameraProfile.xt30III.modelName)") {
                    ForEach(issues) { i in
                        Label(i.message, systemImage: i.severity == .error ? "xmark.octagon" : "info.circle").font(.footnote)
                    }
                }
            }
            Section("Provenance") {
                LabeledContent("Source", value: provenanceLabel(r.provenance.kind))
                if let a = r.provenance.author { LabeledContent("Author", value: a) }
                if let l = r.provenance.license { LabeledContent("Licence", value: l) }
                if let u = r.provenance.sourceURL { Link(u.absoluteString, destination: u) }
                if let n = r.provenance.note { Text(n).font(.footnote).foregroundStyle(Theme.textSecondary) }
                LabeledContent("Cameras", value: r.compatibleCameras.joined(separator: ", "))
            }
        }
        .groupedListStyle()
        .navigationTitle(r.name)
        .inlineNavigationTitle()
        .alert("Rename Recipe", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { var c = r; c.name = newName; env.library.save(c) }
        }
    }

    private func tryInStudio(_ r: FilmRecipe) {
        env.studio.load(r)
        env.router.tab = .studio
    }

    private func provenanceLabel(_ k: RecipeProvenance.Kind) -> String {
        switch k {
        case .filmLabOriginal: "FilmLab original"
        case .userCreated: "Created by you"
        case .duplicated: "Duplicated / tuned"
        case .imported: "Imported file"
        case .cameraSlot: "Read from camera"
        }
    }
}
