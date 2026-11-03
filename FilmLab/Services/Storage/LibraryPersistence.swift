import Foundation

/// File locations. Injectable root so tests use a temporary directory.
struct AppPaths: Sendable {
    let root: URL
    let caches: URL

    var libraryFile: URL { root.appendingPathComponent("library.json") }
    var originals: URL { root.appendingPathComponent("Originals", isDirectory: true) }
    var backups: URL { root.appendingPathComponent("CameraBackups", isDirectory: true) }
    var previewCache: URL { caches.appendingPathComponent("Previews", isDirectory: true) }
    var renderedExports: URL { caches.appendingPathComponent("Exports", isDirectory: true) }

    static func live() -> AppPaths {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FilmLab", isDirectory: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("FilmLab", isDirectory: true)
        return AppPaths(root: support, caches: caches)
    }

    static func temporary() -> AppPaths {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("FilmLab-\(UUID().uuidString)", isDirectory: true)
        return AppPaths(root: base.appendingPathComponent("Support"), caches: base.appendingPathComponent("Caches"))
    }

    func createDirectories() throws {
        for dir in [root, originals, backups, previewCache, renderedExports] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Persisted library, versioned. Bump `currentSchemaVersion` and add a migration step in
/// `LibraryPersistence.migrate` for any breaking change.
struct LibraryDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = LibraryDocument.currentSchemaVersion
    var recipes: [FilmRecipe] = []
    var sets: [RecipeSet] = []
    var assets: [PhotoAsset] = []
    /// Legacy (bundled starter recipes hidden from Explore). Always written empty; kept so the
    /// file still decodes in older builds, whose synthesized decoder requires the key.
    var hiddenStarterIDs: [UUID] = []
}

enum LibraryLoadResult: Equatable {
    case fresh
    case loaded(LibraryDocument)
    /// Written by a newer app version: loaded where possible but never overwritten.
    case newerSchema(found: Int)
    /// Unreadable: moved aside so nothing is lost; a fresh library is started.
    case corrupt(movedTo: URL)
}

enum LibraryPersistence {
    private struct VersionProbe: Decodable { var schemaVersion: Int? }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func load(from url: URL) -> (LibraryLoadResult, LibraryDocument) {
        guard let data = try? Data(contentsOf: url) else { return (.fresh, LibraryDocument()) }
        do {
            let probe = try decoder().decode(VersionProbe.self, from: data)
            let version = probe.schemaVersion ?? 0
            if version > LibraryDocument.currentSchemaVersion {
                return (.newerSchema(found: version), LibraryDocument())
            }
            let doc = try migrate(data, from: version)
            return (.loaded(doc), doc)
        } catch {
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("library.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return (.corrupt(movedTo: aside), LibraryDocument())
        }
    }

    /// Migration chain. v0 = an un-versioned file containing only `recipes` (pre-release format).
    static func migrate(_ data: Data, from version: Int) throws -> LibraryDocument {
        switch version {
        case 0:
            struct V0: Decodable { var recipes: [FilmRecipe] }
            let v0 = try decoder().decode(V0.self, from: data)
            return LibraryDocument(recipes: v0.recipes)
        default:
            return try decoder().decode(LibraryDocument.self, from: data)
        }
    }

    static func save(_ doc: LibraryDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(doc).write(to: url, options: [.atomic])
    }
}

// MARK: - Recipe exchange format

/// Stable, versioned JSON for sharing recipes between devices/apps:
/// `{ "format": "filmlab.recipes", "schemaVersion": 1, "exportedAt": ..., "recipes": [...] }`.
struct RecipeTransferDocument: Codable, Equatable, Sendable {
    static let formatID = "filmlab.recipes"
    static let currentSchemaVersion = 1

    var format: String = RecipeTransferDocument.formatID
    var schemaVersion: Int = RecipeTransferDocument.currentSchemaVersion
    var exportedAt: Date
    var appVersion: String?
    var recipes: [FilmRecipe]
}

enum RecipeTransferError: Error, LocalizedError, Equatable {
    case notFilmLabFile
    case newerSchema(Int)
    case malformed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notFilmLabFile: "This file isn't a FilmLab recipe export."
        case .newerSchema(let v): "This file uses recipe format v\(v). Update FilmLab to import it."
        case .malformed(let m): "The recipe file is damaged: \(m)"
        case .empty: "The file contains no recipes."
        }
    }
}

enum RecipeTransfer {
    static func export(_ recipes: [FilmRecipe], appVersion: String? = nil, now: Date = Date()) throws -> Data {
        try LibraryPersistence.encoder().encode(RecipeTransferDocument(exportedAt: now, appVersion: appVersion, recipes: recipes))
    }

    static func decode(_ data: Data) throws -> [FilmRecipe] {
        struct Header: Decodable { var format: String?; var schemaVersion: Int? }
        let header: Header
        do { header = try LibraryPersistence.decoder().decode(Header.self, from: data) }
        catch { throw RecipeTransferError.notFilmLabFile }
        guard header.format == RecipeTransferDocument.formatID else { throw RecipeTransferError.notFilmLabFile }
        let version = header.schemaVersion ?? 0
        guard version <= RecipeTransferDocument.currentSchemaVersion else { throw RecipeTransferError.newerSchema(version) }
        do {
            let doc = try LibraryPersistence.decoder().decode(RecipeTransferDocument.self, from: data)
            guard !doc.recipes.isEmpty else { throw RecipeTransferError.empty }
            return doc.recipes
        } catch let e as RecipeTransferError {
            throw e
        } catch {
            throw RecipeTransferError.malformed(String(describing: error))
        }
    }

    struct MergeResult: Equatable {
        var merged: [FilmRecipe]
        var added: Int
        var skippedIdentical: Int
        var addedAsCopies: Int
    }

    /// Merges imported recipes into `existing` without ever overwriting a local recipe:
    /// identical content is skipped; ID collisions with different content become copies.
    static func merge(_ incoming: [FilmRecipe], into existing: [FilmRecipe], now: Date = Date()) -> MergeResult {
        var result = existing
        var added = 0, skipped = 0, copies = 0
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for var r in incoming {
            r.settings = r.settings.normalized()
            if let local = byID[r.id] {
                if local.settings == r.settings && local.name == r.name { skipped += 1; continue }
                var copy = r
                copy.id = UUID()
                copy.name = "\(r.name) (Imported)"
                copy.provenance.derivedFrom = r.id
                copy.provenance.kind = .imported
                copy.createdAt = now; copy.updatedAt = now
                result.append(copy); copies += 1
            } else {
                if r.provenance.kind == .userCreated || r.provenance.kind == .duplicated { r.provenance.kind = .imported }
                result.append(r); added += 1
            }
        }
        return MergeResult(merged: result, added: added, skippedIdentical: skipped, addedAsCopies: copies)
    }
}
