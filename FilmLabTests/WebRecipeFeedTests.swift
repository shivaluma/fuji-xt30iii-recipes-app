import Testing
import Foundation
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Web recipe feed (GET /api/recipes)")
struct WebRecipeFeedTests {
    /// Shape of the live response (web/src/app/api/recipes/route.ts), trimmed.
    static let response = Data("""
    {"recipes":[
      {"id":"0F6D8EFB-EC0B-459D-ABF4-E903629F700E","slug":"classic-cuban-negative","name":"CLASSIC CUBAN NEGATIVE",
       "summary":"","filmSimulation":"classicNeg","status":"published",
       "settings":{"filmSimulation":"classicNeg","grainRoughness":{"state":"value","value":"strong"},
                   "highlight":{"state":"value","value":-2},"kelvin":{"state":"notApplicable"}},
       "xTransGeneration":"V","cover":{"url":"/api/media/ed05f30b.webp","kind":"photo"},
       "publishedAt":"2026-11-02T10:36:55.063Z","updatedAt":"2026-11-02T10:38:27.484Z"},
      {"id":"not-a-uuid","slug":"broken","name":"Broken","settings":{"filmSimulation":"provia"}},
      {"id":"7A1B2C3D-0000-4000-8000-000000000001","slug":"no-cover","name":"No Cover",
       "settings":{"filmSimulation":"acros"}}
    ]}
    """.utf8)

    @Test("Decodes recipes, resolves cover URLs and skips invalid entries")
    func decode() throws {
        let base = URL(string: "https://filmlab.example.com")!
        let items = WebRecipeFeed.decode(Self.response, baseURL: base)
        #expect(items.map(\.slug) == ["classic-cuban-negative", "no-cover"])

        let first = try #require(items.first)
        #expect(first.recipe.id == UUID(uuidString: "0F6D8EFB-EC0B-459D-ABF4-E903629F700E"))
        #expect(first.recipe.filmSimulation == .classicNeg)
        #expect(first.recipe.settings.grainRoughness == .value(.strong))
        #expect(first.recipe.settings.highlight == .value(-2))
        #expect(first.recipe.settings.color == .unset)                    // missing → unset, never invented
        #expect(first.recipe.inferredGeneration == .v)
        #expect(first.coverURL?.absoluteString == "https://filmlab.example.com/api/media/ed05f30b.webp")
        #expect(first.coverLabel == "Photo")
        #expect(first.recipe.provenance.sourceURL?.absoluteString == "https://filmlab.example.com/recipes/classic-cuban-negative")

        #expect(items[1].coverURL == nil)
        #expect(items[1].recipe.settings.color == .notApplicable)         // ACROS: normalized
    }

    @Test("Garbage or an error body yields no recipes")
    func garbage() {
        let base = URL(string: "https://filmlab.example.com")!
        #expect(WebRecipeFeed.decode(Data("<html>".utf8), baseURL: base).isEmpty)
        #expect(WebRecipeFeed.decode(Data(#"{"error":"nope"}"#.utf8), baseURL: base).isEmpty)
    }
}
