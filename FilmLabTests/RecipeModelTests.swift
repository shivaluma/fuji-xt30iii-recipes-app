import Testing
import Foundation
import CoreGraphics
import UniformTypeIdentifiers
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Recipe domain model")
struct RecipeModelTests {
    let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()

    @Test("unset, notApplicable and concrete 0 encode distinctly")
    func fieldEncoding() throws {
        let unset = String(decoding: try encoder.encode(RecipeField<Int>.unset), as: UTF8.self)
        let na = String(decoding: try encoder.encode(RecipeField<Int>.notApplicable), as: UTF8.self)
        let zero = String(decoding: try encoder.encode(RecipeField<Int>.value(0)), as: UTF8.self)
        #expect(unset == #"{"state":"unset"}"#)
        #expect(na == #"{"state":"notApplicable"}"#)
        #expect(zero == #"{"state":"value","value":0}"#)
        #expect(Set([unset, na, zero]).count == 3)
    }

    @Test("RecipeField roundtrips through JSON")
    func fieldRoundtrip() throws {
        for f in [RecipeField<Double>.unset, .notApplicable, .value(0), .value(-1.5), .value(4)] {
            let back = try JSONDecoder().decode(RecipeField<Double>.self, from: try encoder.encode(f))
            #expect(back == f)
        }
    }

    @Test("Settings roundtrip preserves every field")
    func settingsRoundtrip() throws {
        var s = RecipeSettings.neutral(.classicNeg)
        s.highlight = .value(-1.5); s.shadow = .value(2); s.kelvin = .value(5200); s.whiteBalance = .value(.colorTemperature)
        s.grainRoughness = .value(.strong); s.grainSize = .value(.large); s.suggestedExposureCompensation = .value(0.67)
        s = s.normalized()
        let back = try JSONDecoder().decode(RecipeSettings.self, from: try encoder.encode(s))
        #expect(back == s)
    }

    @Test("Missing keys decode as unset (tolerant/forward-compatible)")
    func tolerantDecoding() throws {
        let json = #"{"filmSimulation":"acros","shadow":{"state":"value","value":1}}"#
        let s = try JSONDecoder().decode(RecipeSettings.self, from: Data(json.utf8))
        #expect(s.filmSimulation == .acros)
        #expect(s.shadow == .value(1))
        #expect(s.highlight == .unset)
        #expect(s.color == .unset)
    }

    @Test("Dependency rules mark inapplicable fields and never invent values")
    func normalization() {
        var s = RecipeSettings(filmSimulation: .acros)
        s.color = .value(2)
        s.monochromaticWarmCool = .value(3)
        s.kelvin = .value(6000)
        s.whiteBalance = .value(.auto)
        s.grainRoughness = .value(.off)
        s.grainSize = .value(.large)
        let n = s.normalized()
        #expect(n.color == .notApplicable)              // COLOR n/a on ACROS
        #expect(n.monochromaticWarmCool == .value(3))  // mono colour applies to ACROS
        #expect(n.kelvin == .notApplicable)             // WB isn't COLOR TEMPERATURE
        #expect(n.grainSize == .notApplicable)          // grain OFF

        var c = n
        c.filmSimulation = .provia
        c.whiteBalance = .value(.colorTemperature)
        c.grainRoughness = .value(.weak)
        let back = c.normalized()
        #expect(back.color == .unset)                   // applicable again → unset, not 0
        #expect(back.kelvin == .unset)
        #expect(back.grainSize == .unset)
        #expect(back.monochromaticWarmCool == .notApplicable)
        #expect(RecipeSettings(filmSimulation: .sepia).normalized().monochromaticWarmCool == .notApplicable)
    }

    @Test("D RANGE PRIORITY makes DR and tone curve not applicable")
    func drPriority() {
        var s = RecipeSettings.neutral(.provia)
        s.highlight = .value(2)
        s.dRangePriority = .value(.strong)
        let n = s.normalized()
        #expect(n.highlight == .notApplicable)
        #expect(n.shadow == .notApplicable)
        #expect(n.dynamicRange == .notApplicable)
    }

    @Test("Fingerprint is stable and sensitive to every change")
    func fingerprint() {
        let a = RecipeSettings.neutral(.velvia)
        var b = a
        #expect(a.fingerprint == b.fingerprint)
        b.highlight = .value(0.5)
        #expect(a.fingerprint != b.fingerprint)
        var c = a
        c.highlight = .unset
        #expect(c.fingerprint != a.fingerprint) // unset ≠ 0
    }

    @Test("Duplicating gives a new identity with provenance")
    func duplicate() {
        let r = StarterRecipes.all[0]
        let d = r.duplicated()
        #expect(d.id != r.id)
        #expect(d.provenance.kind == .duplicated)
        #expect(d.provenance.derivedFrom == r.id)
        #expect(d.settings == r.settings)
    }

    @Test("Sets always have seven slots and reorder correctly")
    func sets() {
        let ids = (0..<3).map { _ in UUID() }
        var set = RecipeSet(name: "T", slots: ids)
        #expect(set.slots.count == 7)
        set.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(set.slots[0] == ids[1] && set.slots[1] == ids[2] && set.slots[2] == ids[0])
        set.assign(nil, to: .c2)
        #expect(set.filledCount == 2)
        #expect(RecipeSet(name: "x", slots: Array(repeating: UUID(), count: 10)).slots.count == 7)
    }

    @Test("All starter recipes validate cleanly for the X-T30 III")
    func starterRecipesValid() {
        let v = RecipeValidator(profile: .xt30III)
        for r in StarterRecipes.all {
            let errors = v.validate(r.settings).filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(r.name): \(errors.map(\.message))")
        }
        #expect(Set(StarterRecipes.all.map(\.id)).count == StarterRecipes.all.count)
    }
}

@Suite("X-T30 III profile & validation")
struct CameraProfileTests {
    let p = CameraProfile.xt30III

    @Test("Profile identifies sensor and processor separately")
    func identity() {
        #expect(p.modelName == "X-T30 III")
        #expect(p.sensor.contains("X-Trans CMOS 4"))
        #expect(p.processor == "X-Processor 5")
        #expect(p.filmSimulations.count == 20)
        #expect(p.filmSimulations.contains(.realaAce) && p.filmSimulations.contains(.nostalgicNeg) && p.filmSimulations.contains(.eternaBleachBypass))
    }

    @Test("C1–C7 and FS1–FS3 are modelled separately")
    func slotsVsDial() {
        #expect(p.customSlotCount == 7)
        #expect(CameraSlot.allCases.map(\.label) == ["C1", "C2", "C3", "C4", "C5", "C6", "C7"])
        #expect(p.filmSimulationDialSlots == [.fs1, .fs2, .fs3])
        #expect(p.knownQuirks.contains { $0.contains("FS1–FS3") && $0.contains("does not program") })
    }

    @Test("Ranges match the manual where it states them")
    func ranges() {
        #expect(p.capability(.color)?.range == NumericRange(min: -4, max: 4, step: 1))
        #expect(p.capability(.clarity)?.range == NumericRange(min: -5, max: 5, step: 1))
        #expect(p.capability(.kelvin)?.range == NumericRange(min: 2500, max: 10000, step: 10))
        #expect(p.capability(.highlight)?.range?.min == -2)
        #expect(p.capability(.highlight)?.range?.max == 4)
        #expect(p.capability(.highlight)?.valuesStatus == .reportedByThirdParty) // half-steps
        // No PTP capability is claimed as verified on device yet.
        #expect(p.properties.values.allSatisfy { $0.ptpWriteStatus < .verifiedOnDevice })
    }

    @Test("Validator explains out-of-range and dependency problems")
    func validator() {
        var s = RecipeSettings.neutral(.provia)
        s.clarity = .value(7)
        s.highlight = .value(1.25)
        s.whiteBalance = .value(.colorTemperature)
        let issues = RecipeValidator(profile: p).validate(s)
        #expect(issues.contains { $0.key == .clarity && $0.severity == .error })
        #expect(issues.contains { $0.key == .highlight && $0.severity == .error })
        #expect(issues.contains { $0.key == .kelvin && $0.severity == .error && $0.message.contains("Kelvin") })
    }

    @Test("NumericRange contains/clamp")
    func numericRange() {
        let r = NumericRange(min: -2, max: 4, step: 0.5)
        #expect(r.contains(-1.5) && r.contains(4) && !r.contains(4.5) && !r.contains(0.25))
        #expect(r.clamp(9) == 4)
        #expect(r.clamp(0.3) == 0.5)
    }

    @Test("Slot diff marks changed, unchanged, kept and n/a rows")
    func diff() {
        var before = RecipeSettings.neutral(.provia)
        before.shadow = .value(1)
        var new = RecipeSettings(filmSimulation: .acros)
        new.shadow = .value(1)
        new.highlight = .value(2)
        let rows = Dictionary(uniqueKeysWithValues: SlotDiff.rows(before: before, new: new).map { ($0.key, $0) })
        #expect(rows[.filmSimulation]?.kind == .changed)
        #expect(rows[.shadow]?.kind == .unchanged)
        #expect(rows[.highlight]?.kind == .changed)
        #expect(rows[.sharpness]?.kind == .keepsCameraValue)
        #expect(rows[.color]?.kind == .notApplicable)
    }
}
