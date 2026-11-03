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

/// Recipe-family filter for Explore/Library.
enum GenerationFilter: Hashable {
    case all, generation(XTransGeneration), worksOnMyCamera

    func matches(_ r: FilmRecipe, profile: CameraProfile) -> Bool {
        switch self {
        case .all: true
        case .generation(let g): r.inferredGeneration == g
        case .worksOnMyCamera: r.compatibility(with: profile).isUsable
        }
    }
}

/// Chip row: All · X-Trans V · X-Trans IV · Works on <my camera>.
struct GenerationFilterBar: View {
    @Binding var filter: GenerationFilter
    var cameraName: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All cameras", isOn: filter == .all) { filter = .all }
                ForEach(XTransGeneration.allCases) { g in
                    FilterChip(title: g.displayName, isOn: filter == .generation(g)) { filter = filter == .generation(g) ? .all : .generation(g) }
                }
                FilterChip(title: "Works on my \(cameraName)", isOn: filter == .worksOnMyCamera) {
                    filter = filter == .worksOnMyCamera ? .all : .worksOnMyCamera
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .accessibilityIdentifier("generationFilter")
    }
}

/// The recipe catalogue: everything published on the FilmLab website (its public
/// `GET /api/recipes`, cached on this iPhone for offline use) plus your own saved recipes.
/// FilmLab ships no recipes of its own.
struct ExploreView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var situation: Situation?
    @State private var moods: Set<RecipeMood> = []
    @State private var simulation: FilmSimulation?
    @State private var generation: GenerationFilter = .all
    @State private var showFilters = false
    @State private var showImport = false

    private var pool: [FilmRecipe] {
        let library = env.library
        var seen = Set<UUID>()
        return (library.webRecipes + library.recipes).filter { seen.insert($0.id).inserted }
    }

    private var isFiltering: Bool { !query.isEmpty || situation != nil || !moods.isEmpty || simulation != nil || generation != .all }

    private var results: [FilmRecipe] {
        pool.filter { r in
            (query.isEmpty || r.name.localizedCaseInsensitiveContains(query) || r.summary.localizedCaseInsensitiveContains(query)
                || r.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                || r.filmSimulation.displayName.localizedCaseInsensitiveContains(query))
            && (situation?.matches(r) ?? true)
            && (moods.isEmpty || !moods.isDisjoint(with: r.moods))
            && (simulation == nil || r.filmSimulation == simulation)
            && generation.matches(r, profile: env.settings.myProfile)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 14) {
                        situations
                        GenerationFilterBar(filter: $generation, cameraName: env.settings.myCamera.name)
                    }
                    if isFiltering {
                        resultsGrid
                    } else {
                        webSection
                        if !env.library.recipes.isEmpty {
                            carousel(title: "Your Recipes", subtitle: "Saved on this iPhone", recipes: env.library.recipes)
                        }
                        let mono = env.library.webRecipes.filter { $0.filmSimulation.isMonochrome }
                        if !mono.isEmpty {
                            carousel(title: "Black & White", subtitle: "Monochrome looks from FilmLab", recipes: mono)
                        }
                    }
                    if !env.webFeed.hasNeverLoaded || !env.library.recipes.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            Text("Recipes come from the FilmLab website (\(env.webFeed.baseURL.host() ?? "filmlab.requiem.one")) and are kept on this iPhone so they work offline. Save one to keep it even if it's taken down. Photo covers come from the website; other thumbnails are approximate on-device previews on a sample photo of Mt Fuji.")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                .accessibilityIdentifier("exploreSourceNote")
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await env.refreshWebRecipes() }
            .background(Theme.background)
            .navigationTitle("Explore")
            .navigationSubtitleIfAvailable(exploreSubtitle)
            .searchable(text: $query, prompt: "Recipes, simulations, tags")
            .autocorrectionDisabled()
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in RecipeDetailView(recipeID: id) }
            .navigationDestination(for: RecipeListRoute.self) { route in
                RecipeGridScreen(title: route.title, recipes: route.ids.compactMap { env.library.recipe($0) })
            }
            .sheet(isPresented: $showFilters) { filterSheet }
            .sheet(isPresented: $showImport) { RecipeImportView() }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .trailingBar) {
            Button { showFilters = true } label: {
                Image(systemName: moods.isEmpty && simulation == nil
                      ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityLabel("Filters")
        }
        ToolbarItem(placement: .trailingBar) {
            Menu {
                Button("New Recipe", systemImage: "plus") {
                    env.studio.load(FilmRecipe(name: "New Recipe", settings: .neutral()))
                    env.router.tab = .studio
                }
                Button("Import from Image or Text…", systemImage: "text.viewfinder") { showImport = true }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add recipe")
            .accessibilityIdentifier("exploreAdd")
        }
    }

    private var situations: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Situations", subtitle: "Pick a look for what you're shooting")
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

    private var exploreSubtitle: String {
        let feed = env.webFeed
        if feed.isLoading && feed.items.isEmpty { return "Loading recipes…" }
        guard !feed.items.isEmpty else { return "Film recipes for X-Trans IV & V" }
        return "\(feed.items.count) recipes from FilmLab"
    }

    /// The catalogue: recipes published on the FilmLab website, from the same API the site uses.
    @ViewBuilder private var webSection: some View {
        let feed = env.webFeed
        let host = feed.baseURL.host() ?? "the FilmLab website"
        if !feed.items.isEmpty {
            carousel(title: "Latest Recipes", subtitle: updatedLine(feed, host: host), recipes: feed.recipes)
            if let error = feed.lastError {
                Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.gutter)
            }
        } else if feed.isLoading {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Latest Recipes", subtitle: "Loading from \(host)…")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.surface)
                                .frame(width: 290, height: 218)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .redacted(reason: .placeholder)
            }
        } else {
            // Nothing cached and no answer from the website (first launch offline, or the site is down).
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label(feed.lastError == nil ? "No Recipes Yet" : "Recipes Are Offline", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(feed.lastError == nil
                         ? "FilmLab's recipes come from \(host). Pull to refresh to load them."
                         : "FilmLab's recipes come from \(host), and this iPhone couldn't reach it. Connect to the internet and try again — once loaded, they stay available offline.")
                } actions: {
                    Button { Task { await env.refreshWebRecipes() } } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .primaryActionStyle()
                    .accessibilityIdentifier("retryWebRecipes")
                }
                if !env.library.recipes.isEmpty {
                    Text("Your saved recipes are below.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("exploreOffline")
        }
    }

    private func updatedLine(_ feed: WebRecipeFeed, host: String) -> String {
        guard let updated = feed.lastUpdated else { return "From \(host)" }
        return "From \(host) · updated \(updated.formatted(.relative(presentation: .named)))"
    }

    private func carousel(title: String, subtitle: String, recipes: [FilmRecipe]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            NavigationLink(value: RecipeListRoute(title: title, ids: recipes.map(\.id))) {
                SectionHeader(title: title, subtitle: subtitle, actionTitle: "See all", action: {})
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(recipes) { r in
                        NavigationLink(value: r.id) {
                            let web = env.webFeed.item(for: r.id)
                            PhotoRecipeCard(recipe: r, thumbnail: env.thumbnails.thumbnail(for: r), width: 290, saved: env.library.isSaved(r.id),
                                            coverURL: web?.coverURL, coverLabel: web?.coverLabel ?? "Approximate")
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
                          actionTitle: "Clear", action: { query = ""; situation = nil; moods = []; simulation = nil; generation = .all })
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
                    Text("Mood").eyebrowStyle()
                    FlowLayout(spacing: 8) {
                        ForEach(RecipeMood.allCases, id: \.self) { m in
                            FilterChip(title: m.displayName, isOn: moods.contains(m)) {
                                if moods.contains(m) { moods.remove(m) } else { moods.insert(m) }
                            }
                        }
                    }
                    Text("Film simulation").eyebrowStyle()
                    FlowLayout(spacing: 8) {
                        FilterChip(title: "Any", isOn: simulation == nil) { simulation = nil }
                        ForEach(FilmSimulation.allCases) { sim in
                            FilterChip(title: sim.shortName, isOn: simulation == sim) { simulation = sim }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 28) {
            ForEach(recipes) { r in
                NavigationLink(value: r.id) {
                    let web = env.webFeed.item(for: r.id)
                    PhotoRecipeCard(recipe: r, thumbnail: env.thumbnails.thumbnail(for: r), width: nil, saved: env.library.isSaved(r.id),
                                    coverURL: web?.coverURL, coverLabel: web?.coverLabel ?? "Approximate")
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
            RecipeGrid(recipes: recipes).padding(.vertical, 12)
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
        let profile = env.settings.myProfile
        let compat = r.compatibility(with: profile)
        let issues = RecipeValidator(profile: profile).validate(r.settings).filter { $0.severity != .info || !$0.isCapability }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if let t = env.thumbnails.thumbnail(for: r) { CGImageView(image: t, contentMode: .fill) } else { Theme.swatch(for: r.filmSimulation) }
                    }
                    .frame(height: 220).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
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
            Section("Compatibility") {
                LabeledContent("Written for", value: writtenFor(r))
                if saved, r.provenance.kind != .filmLabOriginal {
                    Picker("X-Trans tag", selection: Binding(
                        get: { r.xTransGeneration },
                        set: { var c = r; c.xTransGeneration = $0; env.library.save(c) })) {
                        Text("Not set").tag(XTransGeneration?.none)
                        ForEach(XTransGeneration.allCases) { g in Text(g.displayName).tag(XTransGeneration?.some(g)) }
                    }
                    .accessibilityIdentifier("generationTag")
                }
                Label("\(compat.label) on your \(profile.modelName)", systemImage: compatIcon(compat))
                    .foregroundStyle(compatColor(compat))
                ForEach(issues) { i in
                    Label(i.message, systemImage: i.severity == .error ? "xmark.octagon" : "info.circle").font(.footnote)
                        .foregroundStyle(i.severity == .error ? Theme.textPrimary : Theme.textSecondary)
                }
                NavigationLink("Check every camera") { CameraCompatibilityList(recipe: r) }
            }
            Section("Provenance") {
                LabeledContent("Source", value: env.webFeed.isPublished(r) ? "FilmLab website" : provenanceLabel(r.provenance.kind))
                if let a = r.provenance.author { LabeledContent("Author", value: a) }
                if let l = r.provenance.license { LabeledContent("Licence", value: l) }
                if let u = r.provenance.sourceURL { Link(env.webFeed.isPublished(r) ? "View on the FilmLab website" : u.absoluteString, destination: u) }
                if let n = r.provenance.note { Text(n).font(.footnote).foregroundStyle(Theme.textSecondary) }
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

    private func writtenFor(_ r: FilmRecipe) -> String {
        let cams = r.compatibleCameras.joined(separator: ", ")
        switch (r.inferredGeneration, cams.isEmpty) {
        case let (g?, false): return "\(cams) · \(g.displayName)"
        case let (g?, true): return g.displayName
        case (nil, false): return cams
        case (nil, true): return "Unknown"
        }
    }

    private func tryInStudio(_ r: FilmRecipe) {
        env.studio.load(r)
        env.router.tab = .studio
    }

    private func provenanceLabel(_ k: RecipeProvenance.Kind) -> String {
        switch k {
        case .filmLabOriginal: "FilmLab (earlier app version)"
        case .userCreated: "Created by you"
        case .duplicated: "Duplicated / tuned"
        case .imported: "Imported file"
        case .cameraSlot: "Read from camera"
        }
    }
}

func compatIcon(_ c: RecipeCompatibility) -> String {
    switch c {
    case .supported: "checkmark.circle.fill"
    case .worksWithChanges: "exclamationmark.circle"
    case .notAvailable: "xmark.circle"
    }
}

func compatColor(_ c: RecipeCompatibility) -> Color {
    switch c {
    case .supported: Theme.authentic
    case .worksWithChanges: Theme.warning
    case .notAvailable: Theme.textTertiary
    }
}

/// How one recipe fares on every catalog body, grouped by X-Trans generation.
struct CameraCompatibilityList: View {
    var recipe: FilmRecipe
    var body: some View {
        List {
            ForEach(CameraCatalog.grouped(), id: \.generation) { group in
                Section(group.generation.displayName) {
                    ForEach(group.cameras) { cam in
                        let c = recipe.compatibility(with: cam.profile)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(cam.name).font(.body.weight(.semibold))
                                Spacer()
                                Label(c.label, systemImage: compatIcon(c)).font(.footnote).foregroundStyle(compatColor(c))
                            }
                            switch c {
                            case .supported: EmptyView()
                            case .notAvailable(let why): Text(why).font(.caption).foregroundStyle(Theme.textSecondary)
                            case .worksWithChanges(let issues):
                                ForEach(issues) { Text($0.message).font(.caption).foregroundStyle(Theme.textSecondary) }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Text("Feature support for bodies other than the X-T30 III is community-reported, not verified by FilmLab. Firmware updates can add film simulations (e.g. REALA ACE).")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .groupedListStyle()
        .navigationTitle("Camera compatibility")
        .inlineNavigationTitle()
    }
}
