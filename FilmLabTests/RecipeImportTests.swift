import Testing
import Foundation
import CoreGraphics
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Recipe image/text import")
struct RecipeImportTests {
    struct Fixture: Decodable { var blocks: [OCRTextBlock] }

    static func blocks(_ name: String) throws -> [OCRTextBlock] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ocr-\(name).json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).blocks
    }

    @Test("Card A: values above labels, Kelvin WB, unread digits are flagged not guessed")
    func cardA() throws {
        let d = RecipeCardParser.parse(blocks: try Self.blocks("card-a"))
        let s = d.settings.normalized()
        #expect(d.name == "Overcast Clarity")
        #expect(d.cameraModel == "X-T30 III")
        #expect(d.credit == "@photo_credit")
        #expect(d.sourceNote == "Made with FUJISTYLE APP")
        #expect(s.filmSimulation == .classicChrome)
        #expect(s.whiteBalance == .value(.colorTemperature))
        #expect(s.kelvin == .value(5200))
        #expect(s.wbShiftRed == .value(0) && s.wbShiftBlue == .value(0))
        #expect(s.grainRoughness == .value(.off))
        #expect(s.colorChrome == .value(.strong))
        #expect(s.colorChromeFXBlue == .value(.strong))
        #expect(s.dynamicRange == .value(.dr400))
        #expect(s.highlight == .value(-0.5))
        #expect(s.shadow == .value(-1))
        #expect(s.color == .value(1))
        #expect(s.highISONR == .value(0))           // OCR read "O"
        // The card's lone "0"s for Sharpness/Clarity weren't recognized: unset + flagged.
        #expect(s.sharpness == .unset && s.clarity == .unset)
        #expect(Set(d.missing.keys) == [.sharpness, .clarity])
        #expect(d.unrecognized.isEmpty)
    }

    @Test("Card B: preset WB with shifts, different camera")
    func cardB() throws {
        let d = RecipeCardParser.parse(blocks: try Self.blocks("card-b"))
        let s = d.settings.normalized()
        #expect(d.name == "Indoor Glow")
        #expect(d.cameraModel == "X-T5")
        #expect(d.credit == "credit_two")
        #expect(s.whiteBalance == .value(.daylight))
        #expect(s.kelvin == .notApplicable)
        #expect(s.wbShiftRed == .value(1) && s.wbShiftBlue == .value(-1))
        #expect(s.colorChromeFXBlue == .value(.off))
        #expect(s.highlight == .value(-1.5) && s.shadow == .value(-0.5))
        #expect(s.color == .value(2) && s.sharpness == .value(1) && s.highISONR == .value(1) && s.clarity == .value(0))
        #expect(d.missing.isEmpty)
        let r = d.recipe()
        #expect(r.provenance.kind == .imported)
        #expect(r.provenance.author == "credit_two")
        #expect(r.compatibleCameras.contains("X-T5"))
        #expect(RecipeValidator(profile: .xt30III).validate(r.settings).filter { $0.severity == .error }.isEmpty)
    }

    @Test("Plain text recipe (e.g. pasted from a comment)")
    func plainText() {
        let text = """
        Kodak-ish Summer
        Film Simulation: Classic Negative
        Grain Effect: Weak, Small
        Color Chrome Effect: Strong
        Color Chrome FX Blue: Off
        White Balance: 5600K, +2 Red & −4 Blue
        Dynamic Range: DR200
        Highlight: −1
        Shadow: +1.5
        Color: +3
        Sharpness: −2
        High ISO NR: −4
        Clarity: 0
        ISO: Auto, up to ISO 6400
        Exposure Compensation: +1/3 to +2/3 (typically)
        Something unrelated
        """
        let d = RecipeCardParser.parse(text: text)
        let s = d.settings.normalized()
        #expect(d.name == "Kodak-ish Summer")
        #expect(s.filmSimulation == .classicNeg)
        #expect(s.grainRoughness == .value(.weak) && s.grainSize == .value(.small))
        #expect(s.kelvin == .value(5600) && s.wbShiftRed == .value(2) && s.wbShiftBlue == .value(-4))
        #expect(s.dynamicRange == .value(.dr200))
        #expect(s.highlight == .value(-1) && s.shadow == .value(1.5))
        #expect(s.color == .value(3) && s.sharpness == .value(-2) && s.highISONR == .value(-4) && s.clarity == .value(0))
        #expect(abs((s.suggestedExposureCompensation.concreteValue ?? 0) - 1.0 / 3.0) < 0.01)
        #expect(d.notes == ["ISO: Auto, up to ISO 6400"])
        #expect(d.unrecognized == ["Something unrelated"])
    }

    @Test("Value parsers")
    func values() {
        #expect(RecipeCardParser.number("O") == 0)
        #expect(RecipeCardParser.number("−1.0") == -1)
        #expect(RecipeCardParser.number("+0.5") == 0.5)
        #expect(RecipeCardParser.number("-") == nil)
        #expect(RecipeCardParser.number("+2/3")! > 0.66)
        #expect(RecipeCardParser.filmSimulation("ACROS + R FILTER") == .acrosR)
        #expect(RecipeCardParser.filmSimulation("Eterna Bleach Bypass") == .eternaBleachBypass)
        #expect(RecipeCardParser.filmSimulation("PRO Neg. Hi") == .proNegHi)
        #expect(RecipeCardParser.filmSimulation("Nostalgic Negative") == .nostalgicNeg)
        #expect(RecipeCardParser.filmSimulation("Velvia/VIVID") == .velvia)
        #expect(RecipeCardParser.whiteBalance("Auto White Priority")?.0 == .autoWhitePriority)
        #expect(RecipeCardParser.whiteBalance("Fluorescent Light-2")?.0 == .fluorescent2)
        #expect(RecipeCardParser.cameraModel(in: "Film Recipe X-T30 III Other") == "X-T30 III")
        #expect(RecipeCardParser.cameraModel(in: "Film Recipe X-T5 Other") == "X-T5")
        #expect(RecipeCardParser.cameraModel(in: "for my X100VI") == "X100VI")
        let shift = RecipeCardParser.wbShift("Red: +1 Blue: -1")
        #expect(shift.red == 1 && shift.blue == -1)
    }
}
