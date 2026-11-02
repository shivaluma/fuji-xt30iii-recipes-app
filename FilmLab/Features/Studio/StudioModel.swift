import Foundation
import Observation
import CoreGraphics

/// Studio state: photo, working recipe, previews, compare grid and camera render.
///
/// Stale-frame protection: every render captures `generation`; results are applied only if
/// the generation still matches, and superseded tasks are cancelled. Slider updates are
/// coalesced with a short debounce.
@Observable
@MainActor
final class StudioModel {
    enum CameraRenderState: Equatable {
        case idle
        case rendering
        case failed(String)
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case approximate, camera
        var id: String { rawValue }
    }

    static let previewLongEdge = 1600
    static let thumbnailLongEdge = 480
    static let debounce: Duration = .milliseconds(35)

    let renderer: OfflinePreviewRenderer
    let library: LibraryStore
    var cameraRenderService: CameraRenderService

    private(set) var asset: PhotoAsset?
    /// Working copy of the recipe being tuned. Changing its settings triggers a re-render.
    var recipe: FilmRecipe {
        didSet {
            if oldValue.settings != recipe.settings {
                isDirty = true
                scheduleRender()
            }
        }
    }
    /// The saved/catalog recipe the working copy came from (nil = new).
    private(set) var baseRecipeID: UUID?
    private(set) var isDirty = false

    private(set) var preview: RenderedPreview?
    private(set) var original: RenderedPreview?
    private(set) var histogram: Histogram?
    private(set) var isRendering = false
    private(set) var isLoadingPhoto = false
    var errorMessage: String?

    var displayMode: DisplayMode = .approximate
    private(set) var cameraPreview: RenderedPreview?
    private(set) var cameraRenderState: CameraRenderState = .idle
    private(set) var cameraAvailability: CameraRenderAvailability = .notConnected

    var compareRecipeIDs: [UUID] = []
    private(set) var compareResults: [UUID: RenderedPreview] = [:]

    private(set) var generation = 0
    private var renderTask: Task<Void, Never>?
    private var compareTask: Task<Void, Never>?
    private var compareGeneration = 0
    private var cameraTask: Task<Void, Never>?
    private var cameraGeneration = 0
    /// Number of renders whose result was discarded because a newer request superseded it.
    private(set) var discardedStaleRenders = 0

    init(renderer: OfflinePreviewRenderer, library: LibraryStore, cameraRenderService: CameraRenderService) {
        self.renderer = renderer
        self.library = library
        self.cameraRenderService = cameraRenderService
        let start = StarterRecipes.all.first ?? FilmRecipe(name: "New Recipe", settings: .neutral())
        self.recipe = start
        self.baseRecipeID = start.id
    }

    // MARK: Photo

    private var selectGeneration = 0

    func select(_ asset: PhotoAsset) async {
        guard asset.id != self.asset?.id || original == nil else { return }
        selectGeneration += 1
        let token = selectGeneration
        // Invalidate everything tied to the previous photo before any await.
        generation += 1
        renderTask?.cancel(); compareTask?.cancel(); cameraTask?.cancel()
        cameraGeneration += 1
        preview = nil; original = nil; histogram = nil; cameraPreview = nil
        compareResults = [:]
        cameraRenderState = .idle
        errorMessage = nil
        isLoadingPhoto = true
        do {
            try await renderer.loadSource(asset: asset, url: library.importer.url(for: asset))
            let base = try await renderer.renderOriginal(fingerprint: asset.fingerprint, longEdge: Self.previewLongEdge)
            guard token == selectGeneration else { return } // a newer selection won
            self.asset = asset
            original = base
            isLoadingPhoto = false
            scheduleRender(immediately: true)
            renderCompareGrid()
            await refreshCameraAvailability()
        } catch {
            guard token == selectGeneration else { return }
            isLoadingPhoto = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Recipe

    /// Loads a recipe into the working copy (no camera interaction whatsoever).
    func load(_ r: FilmRecipe) {
        cameraTask?.cancel()
        cameraGeneration += 1
        baseRecipeID = r.id
        recipe = r
        isDirty = false
        cameraPreview = nil
        cameraRenderState = .idle
        if displayMode == .camera { displayMode = .approximate }
    }

    func setFilmSimulation(_ sim: FilmSimulation) {
        var s = recipe.settings
        s.filmSimulation = sim
        recipe.settings = s.normalized()
    }

    /// Whether the working copy can be saved in place (only user-owned library recipes).
    var canSaveInPlace: Bool {
        guard let id = baseRecipeID, let saved = library.recipes.first(where: { $0.id == id }) else { return false }
        return saved.provenance.kind != .filmLabOriginal
    }

    @discardableResult
    func saveChanges() -> FilmRecipe? {
        guard canSaveInPlace else { return nil }
        let saved = library.save(recipe)
        isDirty = false
        return saved
    }

    @discardableResult
    func saveAsNew(name: String) -> FilmRecipe {
        let base = library.recipe(baseRecipeID)
        var new = FilmRecipe(name: name.isEmpty ? "Untitled Recipe" : name, summary: recipe.summary,
                             settings: recipe.settings, tags: recipe.tags, moods: recipe.moods,
                             provenance: base.map {
                                 RecipeProvenance(kind: .duplicated, author: $0.provenance.author, sourceURL: $0.provenance.sourceURL,
                                                  license: $0.provenance.license, derivedFrom: $0.id, note: "Tuned from “\($0.name)” in Studio")
                             } ?? .userCreated)
        new = library.save(new)
        baseRecipeID = new.id
        recipe = new
        isDirty = false
        return new
    }

    func revert() {
        if let base = library.recipe(baseRecipeID) { load(base) }
    }

    // MARK: Rendering

    func scheduleRender(immediately: Bool = false) {
        guard let asset else { return }
        generation += 1
        let gen = generation
        let settings = recipe.settings
        renderTask?.cancel()
        isRendering = true
        renderTask = Task { [weak self, renderer] in
            if !immediately { try? await Task.sleep(for: Self.debounce) }
            guard !Task.isCancelled else { return }
            do {
                let result = try await renderer.render(fingerprint: asset.fingerprint, settings: settings, longEdge: Self.previewLongEdge)
                // Histogram off the main actor (the task itself inherits main-actor isolation).
                let image = result.image
                let hist = await Task.detached(priority: .userInitiated) { Histogram.compute(from: image) }.value
                guard let self else { return }
                guard gen == self.generation, !Task.isCancelled else {
                    self.discardedStaleRenders += 1
                    return
                }
                self.preview = result
                self.histogram = hist
                self.isRendering = false
            } catch is CancellationError {
                // superseded
            } catch {
                guard let self, gen == self.generation else { return }
                self.errorMessage = error.localizedDescription
                self.isRendering = false
            }
        }
    }

    /// Await the in-flight render (used by tests/UI tests).
    func waitForRender() async { await renderTask?.value }

    // MARK: Compare grid

    var compareRecipes: [FilmRecipe] { compareRecipeIDs.compactMap { library.recipe($0) } }

    func setCompare(_ ids: [UUID]) {
        compareRecipeIDs = Array(ids.prefix(9))
        renderCompareGrid()
    }

    /// Renders every grid cell from the same source at the same size (consistent crop/exposure).
    /// Obsolete grid requests are cancelled; results are applied only for the current grid.
    func renderCompareGrid() {
        guard let asset else { return }
        compareTask?.cancel()
        compareGeneration += 1
        let gen = compareGeneration
        let items = compareRecipes.map { ($0.id, $0.settings) }
        compareResults = compareResults.filter { id, _ in items.contains { $0.0 == id } }
        compareTask = Task { [weak self, renderer] in
            for (id, settings) in items {
                guard !Task.isCancelled else { return }
                guard let result = try? await renderer.render(fingerprint: asset.fingerprint, settings: settings, longEdge: Self.thumbnailLongEdge) else { continue }
                guard let self, gen == self.compareGeneration else { return }
                self.compareResults[id] = result
            }
        }
    }

    func waitForCompare() async { await compareTask?.value }

    // MARK: Camera render (separate, explicit action; never writes presets)

    func refreshCameraAvailability() async {
        cameraAvailability = await cameraRenderService.availability(for: asset)
    }

    func renderWithCamera() {
        guard let asset else { return }
        cameraTask?.cancel()
        cameraGeneration += 1
        let token = cameraGeneration
        cameraRenderState = .rendering
        let settings = recipe.settings
        let url = library.importer.url(for: asset)
        let service = cameraRenderService
        cameraTask = Task { [weak self] in
            do {
                let result = try await service.render(asset: asset, sourceURL: url, settings: settings)
                guard let self, token == self.cameraGeneration, !Task.isCancelled, self.asset?.id == asset.id else { return }
                self.cameraPreview = result
                self.cameraRenderState = .idle
                self.displayMode = .camera
            } catch {
                guard let self, token == self.cameraGeneration else { return }
                self.cameraRenderState = error is CancellationError ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func cancelCameraRender() {
        cameraTask?.cancel()
        cameraGeneration += 1
        cameraRenderState = .idle
    }

    /// The image currently shown in the main canvas.
    var displayedPreview: RenderedPreview? {
        displayMode == .camera ? (cameraPreview ?? preview) : preview
    }

    /// True if the camera render no longer matches the current settings.
    var cameraPreviewIsStale: Bool {
        guard let c = cameraPreview else { return false }
        return c.key.settingsFingerprint != recipe.settings.fingerprint
    }

    func exportCurrentJPEG() async throws -> URL {
        guard let asset else { throw PreviewError.sourceNotLoaded }
        let data = try await renderer.exportJPEG(fingerprint: asset.fingerprint, settings: recipe.settings)
        let dir = library.paths.renderedExports
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = recipe.name.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("FilmLab-\(safeName)-approximate.jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}
