import Foundation
#if !FILMLAB_CLI
@testable import FilmLab
#endif

/// Recipe fixtures for unit tests. The app ships no recipes: its catalogue is the FilmLab
/// website's `GET /api/recipes` (`WebRecipeFeed`). These are the former bundled starters, kept
/// with their original IDs so tests (and the legacy-starter migration test) stay meaningful.
///
/// Written for this project (not copied from any website, blog or app). Names and settings are
/// original; any resemblance to a community recipe is coincidental because the setting space is small.
enum TestRecipes {
    static let author = "FilmLab"
    static let license = "Same licence as the FilmLab project"

    private static func make(_ id: String, _ name: String, _ summary: String, moods: [RecipeMood], tags: [String],
                             _ build: (inout RecipeSettings) -> Void, sim: FilmSimulation) -> FilmRecipe {
        var s = RecipeSettings.neutral(sim)
        build(&s)
        let date = Date(timeIntervalSince1970: 1_793_000_000) // fixed so exports are reproducible
        return FilmRecipe(
            id: UUID(uuidString: id)!,
            name: name, summary: summary, settings: s, tags: tags, moods: moods,
            // X-Trans IV recipes also run on X-Trans V bodies; only V-only simulations make a V recipe.
            xTransGeneration: sim == .realaAce || sim == .nostalgicNeg ? .v : .iv,
            provenance: RecipeProvenance(kind: .filmLabOriginal, author: author, license: license),
            createdAt: date, updatedAt: date)
    }

    static let all: [FilmRecipe] = [
        make("6F1C2A10-0001-4A6B-9C11-000000000001", "Harbour Morning", "Soft, cool daylight with gentle shadows. Good for overcast coastlines.",
             moods: [.cool, .lowContrast, .muted], tags: ["landscape", "overcast"], { s in
                 s.whiteBalance = .value(.daylight); s.wbShiftRed = .value(-1); s.wbShiftBlue = .value(2)
                 s.highlight = .value(-1); s.shadow = .value(-1); s.color = .value(-1)
                 s.grainRoughness = .value(.weak); s.grainSize = .value(.small); s.colorChrome = .value(.weak)
             }, sim: .classicChrome),
        make("6F1C2A10-0002-4A6B-9C11-000000000002", "Late Bus Home", "Warm, punchy night-street look with deep shadows and visible grain.",
             moods: [.warm, .highContrast, .cinematic], tags: ["street", "night"], { s in
                 s.whiteBalance = .value(.auto); s.wbShiftRed = .value(3); s.wbShiftBlue = .value(-4)
                 s.highlight = .value(1); s.shadow = .value(2); s.color = .value(1)
                 s.grainRoughness = .value(.strong); s.grainSize = .value(.large); s.colorChrome = .value(.strong)
                 s.highISONR = .value(-2); s.dynamicRange = .value(.dr200)
             }, sim: .classicNeg),
        make("6F1C2A10-0003-4A6B-9C11-000000000003", "Kitchen Window", "Bright, airy and slightly warm. Built for food and interiors in window light.",
             moods: [.warm, .lowContrast], tags: ["interior", "food"], { s in
                 s.whiteBalance = .value(.colorTemperature); s.kelvin = .value(5800); s.wbShiftRed = .value(1); s.wbShiftBlue = .value(-1)
                 s.highlight = .value(-1.5); s.shadow = .value(-1); s.color = .value(1)
                 s.suggestedExposureCompensation = .value(0.67)
             }, sim: .proNegHi),
        make("6F1C2A10-0004-4A6B-9C11-000000000004", "Paper Moon", "Classic, crunchy black-and-white with a red-filter sky.",
             moods: [.blackAndWhite, .highContrast], tags: ["bw", "street"], { s in
                 s.highlight = .value(1.5); s.shadow = .value(2); s.sharpness = .value(1)
                 s.grainRoughness = .value(.strong); s.grainSize = .value(.small); s.clarity = .value(2)
             }, sim: .acrosR),
        make("6F1C2A10-0005-4A6B-9C11-000000000005", "Tea Stain", "Warm-toned monochrome with lifted, gentle shadows.",
             moods: [.blackAndWhite, .vintage, .lowContrast], tags: ["bw", "portrait"], { s in
                 s.highlight = .value(-1); s.shadow = .value(-1.5)
                 s.monochromaticWarmCool = .value(6); s.monochromaticMagentaGreen = .value(-1)
                 s.grainRoughness = .value(.weak); s.grainSize = .value(.large)
             }, sim: .acros),
        make("6F1C2A10-0006-4A6B-9C11-000000000006", "Golden Hour Drive", "Amber highlights and saturated earth tones for low sun.",
             moods: [.warm, .vivid, .vintage], tags: ["travel", "sunset"], { s in
                 s.whiteBalance = .value(.shade); s.wbShiftRed = .value(2); s.wbShiftBlue = .value(-3)
                 s.highlight = .value(0.5); s.shadow = .value(0.5); s.color = .value(2)
                 s.colorChrome = .value(.strong); s.colorChromeFXBlue = .value(.weak)
             }, sim: .nostalgicNeg),
        make("6F1C2A10-0007-4A6B-9C11-000000000007", "Quiet Cinema", "Flat, desaturated grade with teal shadows for video-like stills.",
             moods: [.cinematic, .muted, .lowContrast, .cool], tags: ["cinematic"], { s in
                 s.whiteBalance = .value(.colorTemperature); s.kelvin = .value(5000); s.wbShiftBlue = .value(1)
                 s.highlight = .value(-2); s.shadow = .value(-2); s.color = .value(-2)
                 s.grainRoughness = .value(.weak); s.grainSize = .value(.small); s.clarity = .value(-2)
             }, sim: .eterna),
        make("6F1C2A10-0008-4A6B-9C11-000000000008", "Concrete & Chrome", "Gritty, silvery bleach-bypass look for architecture.",
             moods: [.highContrast, .muted, .cinematic], tags: ["architecture", "urban"], { s in
                 s.highlight = .value(1); s.shadow = .value(1.5); s.color = .value(-1)
                 s.clarity = .value(3); s.sharpness = .value(1); s.colorChromeFXBlue = .value(.strong)
             }, sim: .eternaBleachBypass),
        make("6F1C2A10-0009-4A6B-9C11-000000000009", "Botanical", "Lush greens and clean skies for gardens and hikes.",
             moods: [.vivid, .neutral], tags: ["nature", "landscape"], { s in
                 s.whiteBalance = .value(.daylight)
                 s.highlight = .value(-0.5); s.shadow = .value(0.5); s.color = .value(1)
                 s.colorChrome = .value(.weak); s.colorChromeFXBlue = .value(.strong)
             }, sim: .velvia),
        make("6F1C2A10-000A-4A6B-9C11-00000000000A", "Everyday Neutral", "A faithful, lightly-polished everyday look. A good baseline to tune.",
             moods: [.neutral], tags: ["everyday"], { s in
                 s.whiteBalance = .value(.auto); s.highlight = .value(-0.5); s.colorChrome = .value(.weak)
             }, sim: .realaAce),
        make("6F1C2A10-000B-4A6B-9C11-00000000000B", "Soft Portrait", "Gentle skin tones and smooth highlight roll-off.",
             moods: [.warm, .lowContrast], tags: ["portrait"], { s in
                 s.whiteBalance = .value(.autoWhitePriority); s.wbShiftRed = .value(1)
                 s.highlight = .value(-1); s.shadow = .value(-0.5); s.sharpness = .value(-1); s.clarity = .value(-1)
             }, sim: .astia),
        make("6F1C2A10-000C-4A6B-9C11-00000000000C", "Old Postcard", "Sepia toning with soft contrast for a nostalgic print feel.",
             moods: [.vintage, .blackAndWhite], tags: ["vintage"], { s in
                 s.highlight = .value(-1); s.shadow = .value(-1); s.grainRoughness = .value(.strong); s.grainSize = .value(.large)
             }, sim: .sepia),
    ]
}
