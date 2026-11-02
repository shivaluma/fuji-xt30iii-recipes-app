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
    var hasSeenOnboarding: Bool { didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        experimentalSlotWrites = defaults.bool(forKey: "experimentalSlotWrites")
        showHistogram = defaults.object(forKey: "showHistogram") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
    }
}

/// Recipes, Sets and imported photos. Persists to versioned JSON after every mutation.
@Observable
@MainActor
final class LibraryStore {
    private(set) var recipes: [FilmRecipe] = []
    private(set) var sets: [RecipeSet] = []
    private(set) var assets: [PhotoAsset] = []
    private(set) var hiddenStarterIDs: Set<UUID> = []
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
        hiddenStarterIDs = Set(doc.hiddenStarterIDs)
    }

    private func persist() {
        guard !isReadOnly else { return }
        let doc = LibraryDocument(recipes: recipes, sets: sets, assets: assets, hiddenStarterIDs: Array(hiddenStarterIDs))
        do {
            try LibraryPersistence.save(doc, to: paths.libraryFile)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    // MARK: Recipes

    var catalog: [FilmRecipe] { StarterRecipes.all.filter { !hiddenStarterIDs.contains($0.id) } }

    func recipe(_ id: UUID?) -> FilmRecipe? {
        guard let id else { return nil }
        return recipes.first { $0.id == id } ?? StarterRecipes.all.first { $0.id == id }
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

    /// Saves a starter recipe into the library unchanged (keeps its provenance).
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
        } else if var starter = StarterRecipes.all.first(where: { $0.id == id }) {
            starter.isFavorite = true
            recipes.insert(starter, at: 0)
            persist()
        }
    }

    func hideStarter(_ id: UUID) { hiddenStarterIDs.insert(id); persist() }
    func restoreStarters() { hiddenStarterIDs.removeAll(); persist() }

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

    /// Creates the synthetic demo photos on first launch (never third-party images).
    func ensureDemoAssets() {
        guard !assets.contains(where: { $0.source == .demo }) else { return }
        for scene in DemoImageFactory.scenes.reversed() {
            guard let data = DemoImageFactory.jpegData(for: scene),
                  let asset = try? importer.importData(data, fileName: "\(scene.name).jpg", typeHint: .jpeg,
                                                       source: .demo, note: "FilmLab synthetic test image")
            else { continue }
            _ = addAsset(asset)
        }
    }
}
