import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Client for the FilmLab web backend (web/ in this repo, e.g. hosted on Dokploy).
/// Used for "Extract with AI" and "Publish to Web". Both require the server's admin token.
struct FilmLabWebClient: Sendable {
    var baseURL: URL
    var token: String

    enum WebError: Error, LocalizedError {
        case notConfigured
        case server(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Set the web showcase URL and admin token in Settings first."
            case .server(let m): m
            case .invalidResponse: "The server returned an unexpected response."
            }
        }
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 120
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw WebError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct Err: Decodable { var error: String }
            throw WebError.server((try? JSONDecoder().decode(Err.self, from: data).error) ?? "Server error \(http.statusCode)")
        }
        return data
    }

    func checkHealth() async throws {
        _ = try await send(request("api/health"))
    }

    // MARK: AI extraction

    private struct ExtractResponse: Decodable {
        struct Draft: Decodable {
            var isRecipe: Bool
            var name: String?
            var cameraModel: String?
            /// "IV" / "V" when the server reports it (newer servers); absent on older ones.
            var xTransGeneration: String?
            var credit: String?
            var settings: RecipeSettings?
            var notes: [String]
            var uncertainFields: [String]
            var model: String?
            var issues: [Issue]?
        }
        struct Issue: Decodable { var field: String; var kind: String; var severity: String; var message: String }
        var draft: Draft
    }

    /// Sends an image (downscaled JPEG) and/or text to the server, which asks Claude to read it.
    /// The result is a draft for review — the server stores nothing.
    func extract(image: CGImage?, text: String?) async throws -> RecipeImportDraft {
        var r = request("api/extract", method: "POST")
        let boundary = "FilmLab-\(UUID().uuidString)"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func part(_ name: String, filename: String? = nil, type: String? = nil, _ data: Data) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"".utf8))
            if let filename { body.append(Data("; filename=\"\(filename)\"".utf8)) }
            body.append(Data("\r\n".utf8))
            if let type { body.append(Data("Content-Type: \(type)\r\n".utf8)) }
            body.append(Data("\r\n".utf8)); body.append(data); body.append(Data("\r\n".utf8))
        }
        if let image, let jpeg = Self.jpeg(image, maxEdge: 2000) { part("file", filename: "recipe.jpg", type: "image/jpeg", jpeg) }
        if let text, !text.isEmpty { part("text", Data(text.utf8)) }
        body.append(Data("--\(boundary)--\r\n".utf8))
        r.httpBody = body

        let d = try JSONDecoder().decode(ExtractResponse.self, from: try await send(r)).draft
        guard d.isRecipe, let settings = d.settings else { throw WebError.server("No recipe was found in that image or text.") }
        var draft = RecipeImportDraft()
        draft.name = d.name ?? ""
        draft.cameraModel = d.cameraModel.map { CameraCatalog.recognize($0)?.name ?? $0 }
        draft.xTransGeneration = d.xTransGeneration.flatMap(XTransGeneration.init(rawValue:))
        draft.credit = d.credit
        draft.settings = settings.normalized()
        draft.filmSimulationFound = true
        draft.notes = d.notes
        draft.sourceNote = "read with AI\(d.model.map { " (\($0))" } ?? "")"
        for key in RecipePropertyKey.allCases where Self.isSet(key, settings) { draft.found.insert(key) }
        draft.uncertain = Set(d.uncertainFields.compactMap(RecipePropertyKey.init(rawValue:)))
        draft.reviewMessages = (d.issues ?? []).filter { $0.kind != "uncertain" }.map { ($0.severity == "error", $0.message) }
        return draft
    }

    static func isSet(_ key: RecipePropertyKey, _ s: RecipeSettings) -> Bool {
        let v = SlotDiff.display(key, s)
        return v != "—" && v != "n/a"
    }

    static func jpeg(_ image: CGImage, maxEdge: Int) -> Data? {
        let scale = min(1, Double(maxEdge) / Double(max(image.width, image.height)))
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    // MARK: Publish

    /// Creates or updates the recipe on the web showcase (same FilmLab JSON schema). Returns its page URL.
    func publish(_ recipe: FilmRecipe, published: Bool, story: String?) async throws -> URL {
        struct Payload: Encodable { var recipe: FilmRecipe; var status: String; var body: String? }
        struct Result: Decodable { struct Item: Decodable { var slug: String }; var recipes: [Item] }
        var r = request("api/recipes", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try LibraryPersistence.encoder().encode(Payload(recipe: recipe, status: published ? "published" : "draft", body: story))
        let result = try JSONDecoder().decode(Result.self, from: try await send(r))
        guard let slug = result.recipes.first?.slug else { throw WebError.invalidResponse }
        return baseURL.appendingPathComponent("recipes/\(slug)")
    }
}
