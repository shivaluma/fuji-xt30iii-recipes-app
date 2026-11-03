import Foundation
import Observation
import CoreImage
import UniformTypeIdentifiers

/// User preferences. Experimental hardware features are OFF by default.
@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    /// Allows real-camera slot writes. Requires reading the warning + typed confirmation.
    var experimentalSlotWrites: Bool { didSet { defaults.set(experimentalSlotWrites, forKey: "experimentalSlotWrites") } }
    var showHistogram: Bool { didSet { defaults.set(showHistogram, forKey: "showHistogram") } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    /// Send the phone's location to the paired camera for geotags (camera asks over Bluetooth).
    var shareLocationWithCamera: Bool { didSet { defaults.set(shareLocationWithCamera, forKey: "shareLocationWithCamera") } }
    var hasSeenOnboarding: Bool { didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") } }
    /// After on-device reading, automatically ask the web server's AI when the result is incomplete.
    var autoAIExtraction: Bool { didSet { defaults.set(autoAIExtraction, forKey: "autoAIExtraction") } }
    /// FilmLab web showcase (e.g. https://recipes.example.com). The admin token lives in the Keychain.
    var webBaseURL: String { didSet { defaults.set(webBaseURL, forKey: "webBaseURL") } }
    var webToken: String {
        get { KeychainStore.get("adminToken") ?? "" }
        set { KeychainStore.set(newValue, for: "adminToken"); webTokenRevision += 1 }
    }
    private(set) var webTokenRevision = 0
    /// The body the user shoots with (catalog id). Drives validation, the Tune panel, the film
    /// simulation picker and "Works on my camera". Defaults to the X-T30 III reference body.
    var myCameraID: String { didSet { defaults.set(myCameraID, forKey: "myCameraID") } }
    var myCamera: CameraModelInfo { CameraCatalog.info(id: myCameraID) ?? CameraCatalog.reference }
    var myProfile: CameraProfile { myCamera.profile }

    /// Where public recipes are read from: the Web showcase URL if set, else the FilmLab site.
    var webFeedBaseURL: URL {
        guard let url = URL(string: webBaseURL.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true,
              url.host() != nil else { return WebRecipeFeed.defaultBaseURL }
        return url
    }

    var webClient: FilmLabWebClient? {
        _ = webTokenRevision
        guard let url = URL(string: webBaseURL.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true,
              !webToken.isEmpty else { return nil }
        return FilmLabWebClient(baseURL: url, token: webToken)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        experimentalSlotWrites = defaults.bool(forKey: "experimentalSlotWrites")
        showHistogram = defaults.object(forKey: "showHistogram") as? Bool ?? true
        shareLocationWithCamera = defaults.bool(forKey: "shareLocationWithCamera")
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
        webBaseURL = defaults.string(forKey: "webBaseURL") ?? ""
        autoAIExtraction = defaults.object(forKey: "autoAIExtraction") as? Bool ?? true
        let savedCamera = defaults.string(forKey: "myCameraID")
        myCameraID = savedCamera.flatMap { CameraCatalog.info(id: $0)?.id } ?? CameraCatalog.reference.id
    }
}

/// Recipes, Sets and imported photos. Persists to versioned JSON after every mutation.
@Observable
@MainActor
final class LibraryStore {
    private(set) var recipes: [FilmRecipe] = []
    private(set) var sets: [RecipeSet] = []
    private(set) var assets: [PhotoAsset] = []
    private(set) var loadResult: LibraryLoadResult = .fresh
    private(set) var lastSaveError: String?

    let paths: AppPaths
    let importer: PhotoImporter

    /// True when the library on disk is from a newer app version: nothing is written back.
    var isReadOnly: Bool { if case .newerSchema = loadResult { return true } else { return false } }

    init(paths: AppPaths) {
        self.paths = paths
        self.importer = PhotoImporter(paths: paths)
        try? paths.createDirectories()
        let (result, doc) = LibraryPersistence.load(from: paths.libraryFile)
        loadResult = result
        recipes = doc.recipes
        sets = doc.sets
        assets = doc.assets.filter { FileManager.default.fileExists(atPath: importer.url(for: $0).path) }
        removeLegacyStarterRecipes()
    }

    /// Earlier builds shipped 12 starter recipes; the catalogue is now the FilmLab website. Starters
    /// never were seeded into the library — they got there only when the user saved or favourited
    /// one — so this runs once and is conservative: it removes a starter only while it is still
    /// exactly as shipped (FilmLab-original provenance and `updatedAt` == `createdAt`, i.e. never
    /// saved through `save(_:)`, which bumps `updatedAt` on any edit, rename or re-tag). Edited
    /// copies are the user's own work and stay. Set slots pointing at removed starters are cleared.
    /// A marker file keeps it from ever running again (e.g. on a re-imported old export).
    static let legacyStarterIDs: Set<UUID> = Set((1...12).map { UUID(uuidString: String(format: "6F1C2A10-%04X-4A6B-9C11-%012X", $0, $0))! })

    private func removeLegacyStarterRecipes() {
        let marker = paths.root.appendingPathComponent(".legacy-starters-removed")
        guard !isReadOnly, !FileManager.default.fileExists(atPath: marker.path) else { return }
        let stale = Set(recipes.filter {
            Self.legacyStarterIDs.contains($0.id) && $0.provenance.kind == .filmLabOriginal && $0.updatedAt == $0.createdAt
        }.map(\.id))
        if !stale.isEmpty { delete(stale) }
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    private func persist() {
        guard !isReadOnly else { return }
        let doc = LibraryDocument(recipes: recipes, sets: sets, assets: assets)
        do {
            try LibraryPersistence.save(doc, to: paths.libraryFile)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    // MARK: Recipes

    /// The recipe catalogue: recipes published on the FilmLab website (`WebRecipeFeed`, cached
    /// for offline use). FilmLab ships no recipes of its own; nothing here is in the library until
    /// the user saves or favourites it.
    var webRecipes: [FilmRecipe] = []

    /// Web recipes not saved in the library (for pickers that list "yours, then the rest").
    var unsavedWebRecipes: [FilmRecipe] { webRecipes.filter { !isSaved($0.id) } }

    func recipe(_ id: UUID?) -> FilmRecipe? {
        guard let id else { return nil }
        return recipes.first { $0.id == id } ?? webRecipes.first { $0.id == id }
    }

    func isSaved(_ id: UUID) -> Bool { recipes.contains { $0.id == id } }

    /// Inserts or updates a recipe (normalizing settings; bumping `updatedAt`).
    @discardableResult
    func save(_ recipe: FilmRecipe, now: Date = Date()) -> FilmRecipe {
        var r = recipe
        r.settings = r.settings.normalized()
        r.updatedAt = now
        if let i = recipes.firstIndex(where: { $0.id == r.id }) { recipes[i] = r } else { recipes.insert(r, at: 0) }
        persist()
        return r
    }

    /// Saves a web recipe into the library unchanged (keeps its provenance and link to the site),
    /// so it stays available offline even if the website later removes it.
    func saveToLibrary(_ recipe: FilmRecipe) {
        guard !isSaved(recipe.id) else { return }
        recipes.insert(recipe, at: 0)
        persist()
    }

    @discardableResult
    func duplicate(_ recipe: FilmRecipe) -> FilmRecipe {
        save(recipe.duplicated())
    }

    func delete(_ ids: Set<UUID>) {
        recipes.removeAll { ids.contains($0.id) }
        for i in sets.indices {
            sets[i].slots = sets[i].slots.map { $0.flatMap { ids.contains($0) ? nil : $0 } }
        }
        persist()
    }

    func toggleFavorite(_ id: UUID) {
        if let i = recipes.firstIndex(where: { $0.id == id }) {
            recipes[i].isFavorite.toggle()
            persist()
        } else if var web = webRecipes.first(where: { $0.id == id }) {
            web.isFavorite = true
            recipes.insert(web, at: 0)
            persist()
        }
    }

    func exportData(_ ids: Set<UUID>) throws -> Data {
        let chosen = ids.isEmpty ? recipes : recipes.filter { ids.contains($0.id) }
        return try RecipeTransfer.export(chosen, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    }

    @discardableResult
    func importRecipes(from data: Data) throws -> RecipeTransfer.MergeResult {
        let incoming = try RecipeTransfer.decode(data)
        let result = RecipeTransfer.merge(incoming, into: recipes)
        recipes = result.merged
        persist()
        return result
    }

    // MARK: Sets

    @discardableResult
    func createSet(named name: String) -> RecipeSet {
        let set = RecipeSet(name: name)
        sets.insert(set, at: 0)
        persist()
        return set
    }

    func update(_ set: RecipeSet) {
        guard let i = sets.firstIndex(where: { $0.id == set.id }) else { return }
        var s = set
        s.slots = RecipeSet.padded(s.slots)
        s.updatedAt = Date()
        sets[i] = s
        persist()
    }

    func deleteSet(_ id: UUID) {
        sets.removeAll { $0.id == id }
        persist()
    }

    // MARK: Photos

    func addAsset(_ asset: PhotoAsset) -> PhotoAsset {
        if let existing = assets.first(where: { $0.fingerprint == asset.fingerprint }) {
            importer.delete(asset) // duplicate import: drop the new copy, keep the original one
            return existing
        }
        assets.insert(asset, at: 0)
        persist()
        return asset
    }

    func removeAsset(_ asset: PhotoAsset) {
        assets.removeAll { $0.id == asset.id }
        importer.delete(asset)
        persist()
    }

    /// Sample photos on first launch: Mt Fuji (the default Studio and thumbnail photo) plus the
    /// synthetic colour chart. Libraries from older versions swap their synthetic landscape for
    /// Mt Fuji once; if the user later removes Mt Fuji it stays removed.
    func ensureDemoAssets() {
        let demos = assets.filter { $0.source == .demo }
        let legacyLandscape = demos.filter { $0.originalFileName == "Synthetic Landscape.jpg" }
        let fuji = DemoImageFactory.samplePhotoData()
        if demos.isEmpty {
            let fallback = fuji == nil ? DemoImageFactory.scenes : DemoImageFactory.scenes.filter { $0.name != "Synthetic Landscape" }
            for scene in fallback.reversed() {
                if let data = DemoImageFactory.jpegData(for: scene) {
                    addDemoAsset(data, fileName: "\(scene.name).jpg", note: DemoImageFactory.syntheticNote)
                }
            }
        }
        // Added last so it's first: the default Studio photo and thumbnail reference.
        if let fuji, demos.isEmpty || !legacyLandscape.isEmpty {
            addDemoAsset(fuji, fileName: DemoImageFactory.samplePhotoFileName, note: DemoImageFactory.samplePhotoNote)
            legacyLandscape.forEach(removeAsset)
        }
    }

    private func addDemoAsset(_ data: Data, fileName: String, note: String) {
        guard let asset = try? importer.importData(data, fileName: fileName, typeHint: .jpeg, source: .demo, note: note) else { return }
        _ = addAsset(asset)
    }
}
