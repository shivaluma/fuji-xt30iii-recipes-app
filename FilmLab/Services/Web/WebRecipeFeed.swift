import Foundation
import Observation

/// Published recipes from the FilmLab website: the same public `GET /api/recipes` the site
/// renders (web/src/app/api/recipes/route.ts). Reads need no token. The last good response is
/// cached, so Explore still shows them offline.
@Observable
@MainActor
final class WebRecipeFeed {
    /// The site's canonical origin (web/src/lib/site-config.ts). Settings › Web showcase overrides it.
    nonisolated static let defaultBaseURL = URL(string: "https://filmlab.requiem.one")!

    struct Item: Identifiable, Equatable, Sendable {
        var recipe: FilmRecipe
        var slug: String
        var coverURL: URL?
        /// "photo" | "camera-jpeg" | "approximate-preview" (web `CoverKind`).
        var coverKind: String?
        var id: UUID { recipe.id }

        /// Pill shown on the cover, matching the website's cover labels.
        var coverLabel: String {
            switch coverKind {
            case "camera-jpeg": "Camera JPEG"
            case "approximate-preview": "Approximate"
            default: "Photo"
            }
        }
    }

    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?
    private(set) var baseURL: URL
    private let cacheFile: URL?
    private let session: URLSession

    init(baseURL: URL = WebRecipeFeed.defaultBaseURL, cacheDirectory: URL?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        cacheFile = cacheDirectory?.appendingPathComponent("web-recipes.json")
        if let cacheFile, let data = try? Data(contentsOf: cacheFile) {
            items = Self.decode(data, baseURL: baseURL)
            lastUpdated = (try? cacheFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
    }

    var recipes: [FilmRecipe] { items.map(\.recipe) }

    /// Shows a fixed response instead of fetching (UI tests, which run offline).
    func useSnapshot(_ data: Data) {
        items = Self.decode(data, baseURL: baseURL)
        lastUpdated = Date()
        lastError = nil
    }

    /// Came from this website (a catalogue entry, or a saved copy of one).
    func isPublished(_ recipe: FilmRecipe) -> Bool {
        item(for: recipe.id) != nil || (recipe.provenance.sourceURL?.host() == baseURL.host() && recipe.provenance.sourceURL?.path().hasPrefix("/recipes/") == true)
    }

    /// Never loaded and nothing cached: Explore shows its first-run / offline state.
    var hasNeverLoaded: Bool { items.isEmpty && lastUpdated == nil }

    func item(for id: UUID) -> Item? { items.first { $0.id == id } }

    /// Fetches the published list. On failure the previous (or cached) items stay visible.
    func refresh(baseURL newBase: URL? = nil) async {
        if let newBase, newBase != baseURL {
            baseURL = newBase
            items = []
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/recipes"))
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = Self.decode(data, baseURL: baseURL)
            items = decoded
            lastUpdated = Date()
            lastError = nil
            if let cacheFile {
                try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheFile, options: .atomic)
            }
        } catch {
            lastError = "Couldn't reach \(baseURL.host() ?? "the FilmLab website"). \(items.isEmpty ? "" : "Showing saved results.")"
        }
    }

    // MARK: Decoding (pure; unit-tested)

    private struct Response: Decodable { var recipes: [Lossy<Entry>] }

    private struct Entry: Decodable {
        struct Cover: Decodable { var url: String; var kind: String? }
        var id: String
        var slug: String
        var name: String
        var summary: String?
        var settings: RecipeSettings
        var xTransGeneration: XTransGeneration?
        var cover: Cover?
        var publishedAt: String?
        var updatedAt: String?
    }

    /// Skips entries that don't decode instead of failing the whole list.
    private struct Lossy<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    nonisolated static func decode(_ data: Data, baseURL: URL) -> [Item] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return response.recipes.compactMap(\.value).compactMap { e in
            guard let id = UUID(uuidString: e.id) else { return nil }
            let published = e.publishedAt.flatMap(dates.date(from:)) ?? Date(timeIntervalSince1970: 0)
            let updated = e.updatedAt.flatMap(dates.date(from:)) ?? published
            let page = baseURL.appendingPathComponent("recipes").appendingPathComponent(e.slug)
            let recipe = FilmRecipe(
                id: id, name: e.name, summary: e.summary ?? "", settings: e.settings,
                compatibleCameras: [], xTransGeneration: e.xTransGeneration,
                provenance: RecipeProvenance(kind: .imported, sourceURL: page, note: "Published on \(baseURL.host() ?? "the FilmLab website")"),
                createdAt: published, updatedAt: updated)
            let cover = e.cover.flatMap { URL(string: $0.url, relativeTo: baseURL)?.absoluteURL }
            return Item(recipe: recipe, slug: e.slug, coverURL: cover, coverKind: e.cover?.kind)
        }
    }
}
