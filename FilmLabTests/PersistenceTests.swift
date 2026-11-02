import Testing
import Foundation
import CoreGraphics
import UniformTypeIdentifiers
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Persistence, import/export, migration")
struct PersistenceTests {

    @Test("Export → import roundtrip")
    func transferRoundtrip() throws {
        let recipes = Array(StarterRecipes.all.prefix(3))
        let data = try RecipeTransfer.export(recipes, appVersion: "1.0")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["format"] as? String == "filmlab.recipes")
        #expect(json?["schemaVersion"] as? Int == 1)
        let back = try RecipeTransfer.decode(data)
        #expect(back == recipes)
    }

    @Test("Rejects foreign, newer and empty files with clear errors")
    func transferErrors() throws {
        #expect(throws: RecipeTransferError.notFilmLabFile) { try RecipeTransfer.decode(Data("not json".utf8)) }
        #expect(throws: RecipeTransferError.notFilmLabFile) { try RecipeTransfer.decode(Data(#"{"format":"other"}"#.utf8)) }
        #expect(throws: RecipeTransferError.newerSchema(99)) {
            try RecipeTransfer.decode(Data(#"{"format":"filmlab.recipes","schemaVersion":99,"recipes":[]}"#.utf8))
        }
        let empty = try RecipeTransfer.export([])
        #expect(throws: RecipeTransferError.empty) { try RecipeTransfer.decode(empty) }
    }

    @Test("Merge never overwrites local recipes")
    func merge() {
        let local = StarterRecipes.all[0]
        var changed = local
        changed.settings.highlight = .value(3)
        let fresh = FilmRecipe(name: "New", settings: .neutral())
        let result = RecipeTransfer.merge([local, changed, fresh], into: [local])
        #expect(result.skippedIdentical == 1)
        #expect(result.addedAsCopies == 1)
        #expect(result.added == 1)
        #expect(result.merged.first == local)
        #expect(result.merged.count == 3)
        #expect(Set(result.merged.map(\.id)).count == 3)
    }

    @Test("Library persists across relaunch")
    @MainActor
    func relaunch() throws {
        let paths = AppPaths.temporary()
        let store = LibraryStore(paths: paths)
        let r = store.save(FilmRecipe(name: "Persisted", settings: .neutral(.eterna)))
        let set = store.createSet(named: "Trip")
        var s = set; s.assign(r.id, to: .c3); store.update(s)

        let relaunched = LibraryStore(paths: paths)
        #expect(relaunched.recipes.map(\.name) == ["Persisted"])
        #expect(relaunched.recipes.first?.settings == r.settings)
        #expect(relaunched.sets.first?.slots[2] == r.id)
        if case .loaded = relaunched.loadResult {} else { Issue.record("expected .loaded") }
    }

    @Test("Deleting a recipe clears it from Sets")
    @MainActor
    func deleteClearsSets() {
        let store = LibraryStore(paths: .temporary())
        let r = store.save(FilmRecipe(name: "A", settings: .neutral()))
        var s = store.createSet(named: "S"); s.assign(r.id, to: .c1); store.update(s)
        store.delete([r.id])
        #expect(store.sets[0].slots[0] == nil)
    }

    @Test("v0 (unversioned) library migrates")
    func migrationV0() throws {
        let paths = AppPaths.temporary()
        try paths.createDirectories()
        let t = Date(timeIntervalSince1970: 1_790_000_000) // whole seconds: ISO-8601 has no sub-second precision
        let r = FilmRecipe(name: "Legacy", settings: .neutral(), createdAt: t, updatedAt: t)
        let legacy = try LibraryPersistence.encoder().encode(["recipes": [r]])
        try legacy.write(to: paths.libraryFile)
        let (result, doc) = LibraryPersistence.load(from: paths.libraryFile)
        #expect(result == .loaded(doc))
        #expect(doc.recipes == [r])
        #expect(doc.schemaVersion == LibraryDocument.currentSchemaVersion)
    }

    @Test("Corrupt library is moved aside, never deleted")
    func corrupt() throws {
        let paths = AppPaths.temporary()
        try paths.createDirectories()
        try Data("{{{ nope".utf8).write(to: paths.libraryFile)
        let (result, doc) = LibraryPersistence.load(from: paths.libraryFile)
        guard case .corrupt(let aside) = result else { Issue.record("expected corrupt"); return }
        #expect(FileManager.default.fileExists(atPath: aside.path))
        #expect(doc.recipes.isEmpty)
    }

    @Test("A newer-schema library is not overwritten")
    @MainActor
    func newerSchemaReadOnly() throws {
        let paths = AppPaths.temporary()
        try paths.createDirectories()
        let future = Data(#"{"schemaVersion": 42, "recipes": []}"#.utf8)
        try future.write(to: paths.libraryFile)
        let store = LibraryStore(paths: paths)
        #expect(store.isReadOnly)
        store.save(FilmRecipe(name: "X", settings: .neutral()))
        #expect(try Data(contentsOf: paths.libraryFile) == future)
    }

    @Test("Imported originals are copied, read-only, fingerprinted and de-duplicated")
    @MainActor
    func photoImport() throws {
        let store = LibraryStore(paths: .temporary())
        let data = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[0], size: CGSize(width: 300, height: 200)))
        let a = try store.importer.importData(data, fileName: "x.jpg", typeHint: .jpeg, source: .files)
        let first = store.addAsset(a)
        let b = try store.importer.importData(data, fileName: "x-again.jpg", typeHint: .jpeg, source: .files)
        let second = store.addAsset(b)
        #expect(first.id == second.id)                  // duplicate detected by fingerprint
        #expect(store.assets.count == 1)
        #expect(!FileManager.default.fileExists(atPath: store.importer.url(for: b).path))
        let url = store.importer.url(for: first)
        #expect(try Data(contentsOf: url) == data)      // byte-identical copy
        #expect(!FileManager.default.isWritableFile(atPath: url.path))
        #expect(first.pixelWidth == 300 && first.pixelHeight == 200)
        #expect(!first.isRAW)
        #expect(first.baseLabel == "Original")
    }

    @Test("Camera backups save and load")
    func backups() throws {
        let store = CameraBackupStore(directory: AppPaths.temporary().backups)
        let snap = CameraSlotSnapshot(slot: .c1, name: "A", settings: .neutral(), rawValues: [.init(code: 0xD18E, bytes: Data([7, 0]))],
                                      unknownValues: [], readAt: Date(timeIntervalSince1970: 1_800_000_000), camera: .demoXT30III, completeness: .complete)
        let backup = CameraBackup(createdAt: Date(timeIntervalSince1970: 1_800_000_000), camera: .demoXT30III, reason: "test", snapshots: [snap])
        _ = try store.save(backup)
        let loaded = store.loadAll()
        #expect(loaded == [backup])
        #expect(loaded[0].snapshots[0].rawValues[0].bytes == Data([7, 0])) // raw bytes preserved
    }
}
