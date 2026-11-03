import SwiftUI
import UniformTypeIdentifiers

/// FilmLab recipe export file (versioned JSON).
struct RecipeExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var generation: GenerationFilter = .all
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var importing = false
    @State private var exportDoc: RecipeExportFile?
    @State private var message: String?
    @State private var showSettings = false
    @State private var showImageImport = false

    private var recipes: [FilmRecipe] {
        env.library.recipes.filter {
            (!favoritesOnly || $0.isFavorite) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.filmSimulation.displayName.localizedCaseInsensitiveContains(query))
            && generation.matches($0, profile: env.settings.myProfile)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if env.library.isReadOnly {
                    ExperimentalBanner(text: "This library was saved by a newer FilmLab version and is read-only here. Update the app.")
                }
                if case .corrupt(let url) = env.library.loadResult {
                    ExperimentalBanner(text: "Your library file was damaged and was set aside as \(url.lastPathComponent). A new library was started.")
                }
                Section {
                    NavigationLink { SetsListView() } label: {
                        Label("Sets (\(env.library.sets.count))", systemImage: "square.stack.3d.up")
                    }
                    .accessibilityIdentifier("openSets")
                }
                Section("Recipes") {
                    if recipes.isEmpty {
                        Text(env.library.recipes.isEmpty ? "Save recipes from Explore (they come from the FilmLab website) or create your own in Studio. Saved recipes stay on this iPhone, offline too." : "No matches.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(recipes) { r in
                        row(r)
                    }
                    .onDelete { idx in env.library.delete(Set(idx.map { recipes[$0].id })) }
                }
            }
            .groupedListStyle()
            .navigationTitle("Library")
            .themedNavigationBar()
            .searchable(text: $query)
            .navigationDestination(for: UUID.self) { RecipeDetailView(recipeID: $0) }
            .toolbar { toolbar }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let r = try env.library.importRecipes(from: Data(contentsOf: url))
                    message = "Imported \(r.added) recipe(s). \(r.addedAsCopies) added as copies, \(r.skippedIdentical) already present."
                } catch {
                    message = error.localizedDescription
                }
            }
            .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                          document: exportDoc, contentType: .json, defaultFilename: "FilmLab Recipes") { _ in exportDoc = nil }
            .alert("Library", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showImageImport) { RecipeImportView() }
        }
    }

    private func row(_ r: FilmRecipe) -> some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selection.contains(r.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(r.id) ? Theme.accent : Theme.textSecondary)
                    .onTapGesture { toggle(r.id) }
            }
            Group {
                if let t = env.thumbnails.thumbnail(for: r) { CGImageView(image: t, contentMode: .fill) } else { Theme.swatch(for: r.filmSimulation) }
            }
            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { env.thumbnails.request(r) }
            if selecting {
                rowText(r).contentShape(Rectangle()).onTapGesture { toggle(r.id) }
            } else {
                NavigationLink(value: r.id) { rowText(r) }
            }
        }
        .swipeActions(edge: .leading) {
            Button { env.library.toggleFavorite(r.id) } label: { Image(systemName: "heart") }.tint(Theme.accent)
        }
    }

    private func rowText(_ r: FilmRecipe) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(r.name).font(.body).tracking(-0.3)
                if r.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent) }
            }
            Text("\(r.filmSimulation.displayName)\(r.inferredGeneration.map { " · \($0.displayName)" } ?? "") · \(env.webFeed.isPublished(r) ? "FilmLab website" : "Yours")")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .leadingBar) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .trailingBar) {
            Menu {
                Toggle("Favorites only", isOn: $favoritesOnly)
                Picker("Cameras", selection: $generation) {
                    Text("All cameras").tag(GenerationFilter.all)
                    ForEach(XTransGeneration.allCases) { g in Text(g.displayName).tag(GenerationFilter.generation(g)) }
                    Text("Works on my \(env.settings.myCamera.name)").tag(GenerationFilter.worksOnMyCamera)
                }
                Button(selecting ? "Done Selecting" : "Select", systemImage: "checkmark.circle") {
                    selecting.toggle(); selection.removeAll()
                }
                if selecting {
                    Button("Export Selected (\(selection.count))", systemImage: "square.and.arrow.up") { export(selection) }
                        .disabled(selection.isEmpty)
                    Button("Delete Selected (\(selection.count))", systemImage: "trash", role: .destructive) {
                        env.library.delete(selection); selection.removeAll()
                    }
                    .disabled(selection.isEmpty)
                }
                Divider()
                Button("Import from Image or Text…", systemImage: "text.viewfinder") { showImageImport = true }
                Button("Import Recipes…", systemImage: "square.and.arrow.down") { importing = true }
                Button("Export All…", systemImage: "square.and.arrow.up") { export([]) }
                    .disabled(env.library.recipes.isEmpty)
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Library actions")
        }
    }

    private func export(_ ids: Set<UUID>) {
        do { exportDoc = RecipeExportFile(data: try env.library.exportData(ids)) }
        catch { message = error.localizedDescription }
    }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""
    @State private var showWriteWarning = false

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Section {
                    Picker("My camera", selection: $settings.myCameraID) {
                        ForEach(CameraCatalog.grouped(), id: \.generation) { group in
                            Section(group.generation.displayName) {
                                ForEach(group.cameras) { cam in Text(cam.name).tag(cam.id) }
                            }
                        }
                    }
                    .accessibilityIdentifier("myCameraPicker")
                } header: {
                    Text("Camera")
                } footer: {
                    let cam = settings.myCamera
                    Text("\(cam.sensor) · \(cam.processor) · takes \(cam.generation.displayName) recipes. Studio, Tune and compatibility checks use this body. "
                         + (cam.status >= .verifiedInDocs ? "Ranges checked against the owner's manual." : "Feature support is community-reported, not verified by FilmLab."))
                }
                Section("Studio") {
                    Toggle("Show histogram", isOn: $settings.showHistogram)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    Button("Clear preview caches") { Task { await env.renderer.clearCaches(includingDisk: true) } }
                }
                Section {
                    Toggle("Experimental camera slot writes", isOn: Binding(
                        get: { settings.experimentalSlotWrites },
                        set: { on in
                            if on { showWriteWarning = true } else { settings.experimentalSlotWrites = false; env.camera.refreshWritability() }
                        }))
                        .accessibilityIdentifier("experimentalWritesToggle")
                } header: {
                    Text("Hardware (experimental)")
                } footer: {
                    Text("Writing C1–C7 over USB uses unofficial, community-documented protocol details that have NOT been verified by FilmLab. It is offered only on the X-T30 III, the one body with community reports; other recognised cameras are read-only. It may change camera settings unexpectedly and may affect your warranty. Off by default. Demo mode never needs this.")
                }
                WebShowcaseSection()
                Section("About") {
                    LabeledContent("Preview engine", value: FilmLookEngine.version)
                    LabeledContent("Recipe format", value: "\(RecipeTransferDocument.formatID) v\(RecipeTransferDocument.currentSchemaVersion)")
                    Text("FilmLab is not affiliated with FUJIFILM. Film simulation names are FUJIFILM trademarks, used to identify camera settings. Previews are approximations.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .formPage()
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showWriteWarning) {
                NavigationStack {
                    Form {
                        Section {
                            ExperimentalBanner(text: "Experimental hardware integration")
                            Text("""
                            • FilmLab will read and back up all seven custom slots before the first write in each session.
                            • Every write shows a per-setting diff, needs an explicit tap, and is read back and verified.
                            • There is no automatic rollback. If a write is interrupted, the slot's state is unknown until re-read.
                            • Community sources warn that third-party USB access may affect your Fujifilm warranty.
                            • Use a sacrificial slot for your first test.
                            """).font(.footnote)
                        }
                        Section("Type ENABLE to continue") {
                            TextField("ENABLE", text: $confirmText)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("enableWritesField")
                        }
                    }
                    .navigationTitle("Enable Writes?")
                    .inlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showWriteWarning = false; confirmText = "" } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Enable") {
                                settings.experimentalSlotWrites = true
                                env.camera.refreshWritability()
                                showWriteWarning = false
                                confirmText = ""
                            }
                            .disabled(confirmText != "ENABLE")
                        }
                    }
                }
            }
        }
    }
}

/// Connection to the FilmLab web showcase (the Next.js app in web/, e.g. hosted on Dokploy).
struct WebShowcaseSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var token = ""
    @State private var status: String?

    var body: some View {
        @Bindable var settings = env.settings
        Section {
            TextField("https://recipes.example.com", text: $settings.webBaseURL)
                .autocorrectionDisabled()
                .accessibilityLabel("Web showcase URL")
            SecureField("Admin token", text: $token)
                .onSubmit { env.settings.webToken = token }
            Button("Save & Test Connection") {
                env.settings.webToken = token
                Task {
                    guard let client = env.settings.webClient else { status = "Enter an http(s) URL and the token."; return }
                    do { try await client.checkHealth(); status = "Connected." } catch { status = error.localizedDescription }
                }
            }
            if let status { Text(status).font(.footnote).foregroundStyle(Theme.textSecondary) }
            Toggle("Use AI when on-device reading is incomplete", isOn: $settings.autoAIExtraction)
        } header: {
            Text("Web showcase")
        } footer: {
            Text("Used for “Extract with AI” and “Publish to Web”. Recipe images are read on this iPhone first; only incomplete results are sent to your server for AI reading. The token is stored in the iOS Keychain and sent only to this server.")
        }
        .onAppear { token = env.settings.webToken }
    }
}
