import Testing
import Foundation
#if !FILMLAB_CLI
@testable import FilmLab
#endif

/// The Swift catalog must match shared/camera-catalog.json (also used by the web).
@Suite("Camera catalog parity with shared/camera-catalog.json")
struct CameraCatalogParityTests {
    struct JRange: Decodable, Equatable { var min: Double; var max: Double; var step: Double }
    struct JCamera: Decodable {
        var id: String; var name: String; var aliases: [String]; var sensor: String; var processor: String
        var xTransGeneration: String; var filmSimulations: String; var unsupported: [String]; var ranges: [String: JRange]
        var customSlots: Int; var hasFilmSimulationDial: Bool; var status: String; var ptp: String; var notes: [String]
    }
    struct JCatalog: Decodable {
        var schemaVersion: Int
        var baseRanges: [String: JRange]
        var filmSimulationSets: [String: [String]]
        var cameras: [JCamera]
    }

    static func load() throws -> JCatalog {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/camera-catalog.json")
        return try JSONDecoder().decode(JCatalog.self, from: Data(contentsOf: url))
    }

    static func r(_ n: NumericRange?) -> JRange? { n.map { JRange(min: $0.min, max: $0.max, step: $0.step) } }

    @Test("Base ranges and film simulation sets match")
    func basics() throws {
        let j = try Self.load()
        #expect(j.schemaVersion == 1)
        #expect(Set(j.baseRanges.keys) == Set(CameraCatalog.baseRanges.keys.map(\.rawValue)))
        for (k, v) in j.baseRanges { #expect(Self.r(CameraCatalog.baseRanges[RecipePropertyKey(rawValue: k)!]) == v, "\(k)") }
        #expect(Set(j.filmSimulationSets.keys) == Set(CameraCatalog.filmSimulationSets.keys))
        for (k, v) in j.filmSimulationSets { #expect(CameraCatalog.filmSimulationSets[k]?.map(\.rawValue) == v, "\(k)") }
    }

    @Test("Every body matches field by field, in order")
    func bodies() throws {
        let j = try Self.load()
        #expect(j.cameras.map(\.id) == CameraCatalog.all.map(\.id))
        for (jc, sc) in zip(j.cameras, CameraCatalog.all) {
            #expect(jc.name == sc.name && jc.aliases == sc.aliases, "\(jc.id)")
            #expect(jc.sensor == sc.sensor && jc.processor == sc.processor, "\(jc.id)")
            #expect(jc.xTransGeneration == sc.generation.rawValue, "\(jc.id)")
            #expect(j.filmSimulationSets[jc.filmSimulations] == sc.filmSimulations.map(\.rawValue), "\(jc.id)")
            #expect(Set(jc.unsupported) == Set(sc.unsupported.map(\.rawValue)), "\(jc.id)")
            #expect(Set(jc.ranges.keys) == Set(sc.rangeOverrides.keys.map(\.rawValue)), "\(jc.id)")
            for (k, v) in jc.ranges { #expect(Self.r(sc.rangeOverrides[RecipePropertyKey(rawValue: k)!]) == v, "\(jc.id) \(k)") }
            #expect(jc.customSlots == sc.customSlots && jc.hasFilmSimulationDial == sc.hasFilmSimulationDial, "\(jc.id)")
            #expect(jc.status == sc.status.rawValue && jc.ptp == sc.ptp.rawValue, "\(jc.id)")
            #expect(jc.notes == sc.notes, "\(jc.id)")
        }
    }

    @Test("Effective profile ranges = base + overrides; unsupported keys are off")
    func profiles() throws {
        let j = try Self.load()
        for jc in j.cameras where jc.id != CameraProfile.xt30III.catalogID {
            let p = try #require(CameraCatalog.info(id: jc.id)).profile
            for key in RecipePropertyKey.allCases {
                let cap = try #require(p.capability(key))
                #expect(cap.isSupported == !jc.unsupported.contains(key.rawValue), "\(jc.id) \(key)")
                if cap.isSupported, let expected = jc.ranges[key.rawValue] ?? j.baseRanges[key.rawValue] {
                    #expect(Self.r(cap.range) == expected, "\(jc.id) \(key)")
                }
            }
        }
    }

    @Test("X-T30 III stays the manual-checked reference profile")
    func reference() {
        #expect(CameraCatalog.reference.id == "x-t30-iii")
        #expect(CameraCatalog.reference.profile == CameraProfile.xt30III)
        #expect(CameraProfile.xt30III.generation == .v)
        #expect(CameraProfile.xt30III.allowsSlotWrites)
        for cam in CameraCatalog.all where cam.id != "x-t30-iii" {
            #expect(!cam.profile.allowsSlotWrites, "\(cam.name) must stay read-only/profile-only")
            #expect(cam.profile.dataStatus == .reportedByThirdParty)
        }
    }
}

@Suite("Camera recognition & X-Trans generation")
struct CameraRecognitionTests {
    @Test("Recognises catalog bodies in free text, longest match first", arguments: [
        ("X-T30 III", "X-T30 III"), ("FUJIFILM X-T30 Mark III", "X-T30 III"), ("x-t30iii", "X-T30 III"),
        ("X-T30 II", "X-T30 II"), ("Fujifilm X-T30 Mark II", "X-T30 II"), ("X-T30", "X-T30"), ("XT30 recipe", "X-T30"),
        ("X-T50", "X-T50"), ("X-T5", "X-T5"), ("made on my xt5 yesterday", "X-T5"), ("X-T3", "X-T3"), ("X-T4", "X-T4"),
        ("X100VI", "X100VI"), ("X100V", "X100V"), ("X100 VI", "X100VI"),
        ("X-H2S", "X-H2S"), ("X-H2", "X-H2"), ("x-s20", "X-S20"), ("X-S10", "X-S10"), ("X-E5", "X-E5"), ("X-E4", "X-E4"),
        ("X-Pro3", "X-Pro3"), ("X-M5", "X-M5"), ("Film Recipe X-T30 III Other", "X-T30 III"),
    ])
    func recognize(_ text: String, _ expected: String) {
        #expect(CameraCatalog.recognize(text)?.name == expected, "\(text)")
    }

    @Test("Unknown or partial models aren't recognised", arguments: ["GFX100S", "X-T200", "X-A7", "XT300", "BOXE4", "Classic Chrome", ""])
    func unknown(_ text: String) {
        #expect(CameraCatalog.recognize(text) == nil, "\(text)")
    }

    @Test("Generation from text", arguments: [
        ("X-Trans IV", XTransGeneration?.some(.iv)), ("X-TRANS 5 HR", .v), ("X-Trans CMOS 4 sensor", .iv), ("xtrans v recipe", .v),
        ("X Trans V", .v), ("X-Trans III", nil), ("X-Trans II recipe", nil), ("Classic Neg", nil),
    ])
    func generation(_ text: String, _ expected: XTransGeneration?) {
        #expect(XTransGeneration.detect(in: text) == expected, "\(text)")
    }

    @Test("Generation inference: explicit > V-only simulation > recognised camera > unknown")
    func inference() {
        var r = FilmRecipe(name: "t", settings: .neutral(.classicChrome), compatibleCameras: ["X-T4"])
        #expect(r.inferredGeneration == .iv)
        r.xTransGeneration = .v
        #expect(r.inferredGeneration == .v)
        let reala = FilmRecipe(name: "t", settings: .neutral(.realaAce), compatibleCameras: ["X-T4"])
        #expect(reala.inferredGeneration == .v)
        #expect(FilmRecipe(name: "t", settings: .neutral(.nostalgicNeg), compatibleCameras: []).inferredGeneration == .v)
        #expect(FilmRecipe(name: "t", settings: .neutral(.provia), compatibleCameras: []).inferredGeneration == nil)
        #expect(FilmRecipe(name: "t", settings: .neutral(.provia), compatibleCameras: ["GFX100S", "X-S20"]).inferredGeneration == .v)
        // The legacy default "X-T30 III" only counts when it's the sole entry.
        #expect(FilmRecipe(name: "t", settings: .neutral(.classicChrome), compatibleCameras: ["X-T30 III", "X100V"]).inferredGeneration == .iv)
        #expect(FilmRecipe(name: "t", settings: .neutral(.classicChrome), compatibleCameras: ["X100V", "X-T30 III"]).inferredGeneration == .iv)
        #expect(FilmRecipe(name: "t", settings: .neutral(.classicChrome), compatibleCameras: ["X-T30 III"]).inferredGeneration == .v)
        #expect(FilmRecipe(name: "t", settings: .neutral(.classicChrome), compatibleCameras: ["X-T30 III", "GFX100S"]).inferredGeneration == nil)
    }

    @Test("Fixture recipes are tagged: V only when they need a V simulation")
    func fixtureTags() {
        for r in TestRecipes.all {
            let vOnly = r.filmSimulation == .realaAce || r.filmSimulation == .nostalgicNeg
            #expect(r.xTransGeneration == (vOnly ? .v : .iv), "\(r.name)")
        }
    }
}

@Suite("Per-model validation & compatibility")
struct CameraCompatibilityTests {
    func profile(_ name: String) throws -> CameraProfile { try #require(CameraCatalog.profile(for: name)) }

    @Test("CLASSIC Neg. isn't available on the X-T3")
    func classicNegXT3() throws {
        let c = RecipeCompatibility.evaluate(.neutral(.classicNeg), on: try profile("X-T3"))
        guard case .notAvailable(let why) = c else { Issue.record("expected notAvailable, got \(c)"); return }
        #expect(why.contains("X-T3"))
        #expect(RecipeCompatibility.evaluate(.neutral(.classicNeg), on: try profile("X-T4")) == .supported)
    }

    @Test("REALA ACE isn't available on the X-T4; NOSTALGIC Neg. works on the X-S20")
    func realaXT4() throws {
        #expect(!RecipeCompatibility.evaluate(.neutral(.realaAce), on: try profile("X-T4")).isUsable)
        #expect(RecipeCompatibility.evaluate(.neutral(.nostalgicNeg), on: try profile("X-S20")) == .supported)
    }

    @Test("ETERNA BLEACH BYPASS isn't on the X100V or X-Pro3")
    func bleach() throws {
        #expect(!RecipeCompatibility.evaluate(.neutral(.eternaBleachBypass), on: try profile("X100V")).isUsable)
        #expect(!RecipeCompatibility.evaluate(.neutral(.eternaBleachBypass), on: try profile("X-Pro3")).isUsable)
        #expect(RecipeCompatibility.evaluate(.neutral(.eternaBleachBypass), on: try profile("X-E4")).isUsable)
    }

    @Test("Clarity is unsupported on the X-T30: non-zero needs changes, zero is harmless")
    func clarityXT30() throws {
        var s = RecipeSettings.neutral(.classicChrome)
        s.clarity = .value(2)
        let c = RecipeCompatibility.evaluate(s, on: try profile("X-T30"))
        guard case .worksWithChanges(let issues) = c else { Issue.record("expected worksWithChanges, got \(c)"); return }
        #expect(issues.contains { $0.key == .clarity && $0.message.contains("X-T30") })
        s.clarity = .value(0)
        #expect(RecipeCompatibility.evaluate(s, on: try profile("X-T30")) == .supported)
        // The X-T30 II (later X-Trans IV) has Clarity.
        s.clarity = .value(2)
        #expect(RecipeCompatibility.evaluate(s, on: try profile("X-T30 II")) == .supported)
    }

    @Test("Half-step Highlight needs changes on the X-T3 (whole steps)")
    func halfStepsXT3() throws {
        var s = RecipeSettings.neutral(.classicChrome)
        s.highlight = .value(-0.5)
        #expect(!(RecipeCompatibility.evaluate(s, on: try profile("X-T3")) == .supported))
        s.highlight = .value(-1)
        #expect(RecipeCompatibility.evaluate(s, on: try profile("X-T3")) == .supported)
    }

    @Test("Dependency hints don't count as camera incompatibility")
    func dependencyHintsIgnored() throws {
        var s = RecipeSettings.neutral(.acros)
        s.color = .value(2) // "COLOR doesn't apply to monochrome" is a hint for every body
        #expect(RecipeCompatibility.evaluate(s, on: try profile("X-T4")) == .supported)
    }

    @Test("Non-reference bodies get one summary source note, not one per field")
    func summaryNote() throws {
        var s = RecipeSettings.neutral(.classicChrome)
        s.highlight = .value(1); s.shadow = .value(-1)
        let notes = RecipeValidator(profile: try profile("X-T4")).validate(s).filter { $0.severity == .info }
        #expect(notes.count == 1)
        #expect(notes[0].message.contains("community-reported"))
    }

    @Test("Every X-Trans IV fixture works on the X-T4 and every fixture on the X-T30 III")
    func fixturesAcrossBodies() throws {
        let xt4 = try profile("X-T4")
        for r in TestRecipes.all where r.xTransGeneration == .iv {
            #expect(r.compatibility(with: xt4).isUsable, "\(r.name)")
        }
        for r in TestRecipes.all { #expect(r.compatibility(with: .xt30III) == .supported, "\(r.name)") }
    }

    @Test("Tune panel marks settings the body lacks as unavailable")
    func tunePanel() throws {
        let params = TuneParameter.all(for: try profile("X-T3"))
        #expect(params.first { $0.id == "clarity" }?.unavailable != nil)
        #expect(params.first { $0.id == "ccb" }?.unavailable != nil)
        #expect(params.first { $0.id == "highlight" }?.unavailable == nil)
        #expect(TuneParameter.all(for: .xt30III).allSatisfy { $0.unavailable == nil })
        // X-T3 Highlight steps in whole stops.
        var zero = RecipeSettings.neutral(.provia)
        zero.highlight = .value(0)
        let hl = try #require(params.first { $0.id == "highlight" })
        #expect(hl.step(zero, 1).highlight == .value(1))
        let ref = try #require(TuneParameter.all(for: .xt30III).first { $0.id == "highlight" })
        #expect(ref.step(zero, 1).highlight == .value(0.5))
    }
}

@Suite("Recipe JSON xTransGeneration")
struct GenerationJSONTests {
    @Test("Round-trips with and without the tag; older files decode")
    func roundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // whole seconds: JSON dates are ISO-8601
        let tagged = FilmRecipe(name: "Tagged", settings: .neutral(.classicChrome), xTransGeneration: .iv, createdAt: date, updatedAt: date)
        let data = try LibraryPersistence.encoder().encode(tagged)
        #expect(String(decoding: data, as: UTF8.self).contains("\"xTransGeneration\" : \"IV\""))
        #expect(try LibraryPersistence.decoder().decode(FilmRecipe.self, from: data) == tagged)

        let untagged = FilmRecipe(name: "Untagged", settings: .neutral(.classicChrome), createdAt: date, updatedAt: date)
        let data2 = try LibraryPersistence.encoder().encode(untagged)
        #expect(!String(decoding: data2, as: UTF8.self).contains("xTransGeneration"))
        #expect(try LibraryPersistence.decoder().decode(FilmRecipe.self, from: data2) == untagged)

        // Explicit null (as the web may send) decodes to nil.
        var obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj["xTransGeneration"] = NSNull()
        let withNull = try JSONSerialization.data(withJSONObject: obj)
        #expect(try LibraryPersistence.decoder().decode(FilmRecipe.self, from: withNull).xTransGeneration == nil)
    }

    @Test("Transfer documents keep schema version 1 and carry the tag")
    func transfer() throws {
        let doc = RecipeTransferDocument(exportedAt: Date(), appVersion: "test", recipes: [TestRecipes.all[0]])
        let data = try LibraryPersistence.encoder().encode(doc)
        let back = try LibraryPersistence.decoder().decode(RecipeTransferDocument.self, from: data)
        #expect(back.schemaVersion == 1)
        #expect(back.recipes.first?.xTransGeneration == TestRecipes.all[0].xTransGeneration)
    }
}

@Suite("Import: camera model & generation")
struct ImportGenerationTests {
    @Test("Camera label line sets the model and generation")
    func cameraLine() {
        let d = RecipeCardParser.parse(text: """
        Summer Bus
        Camera: Fujifilm X-S20
        Film Simulation: Classic Chrome
        Highlight: -1
        """)
        #expect(d.cameraModel == "X-S20")
        #expect(d.resolvedGeneration == .v)
        #expect(d.writtenForLabel == "Written for X-S20 · X-Trans V")
        #expect(d.otherSettings.isEmpty)
        let r = d.recipe()
        #expect(r.compatibleCameras == ["X-S20"])
        #expect(r.xTransGeneration == .v)
    }

    @Test("Stated generation wins; recipes without camera info stay unknown")
    func statedGeneration() {
        let d = RecipeCardParser.parse(text: """
        Kodak-ish
        My X-Trans IV recipe
        Film Simulation: Classic Negative
        """)
        #expect(d.xTransGeneration == .iv)
        #expect(d.recipe().xTransGeneration == .iv)
        let plain = RecipeCardParser.parse(text: "Plain\nFilm Simulation: Provia")
        #expect(plain.resolvedGeneration == nil)
        #expect(plain.recipe().compatibleCameras.isEmpty)
        #expect(plain.writtenForLabel == nil)
    }

    @Test("A V-only simulation implies X-Trans V even for an X-Trans IV camera line")
    func vOnly() {
        let d = RecipeCardParser.parse(text: "Neg\nCamera: X-T4\nFilm Simulation: Nostalgic Neg")
        #expect(d.cameraModel == "X-T4")
        #expect(d.resolvedGeneration == .v)
    }

    @Test("Model strings are normalised to catalog names")
    func normalised() {
        #expect(RecipeCardParser.cameraModel(in: "for my fujifilm x-t30 mark ii") == "X-T30 II")
        #expect(RecipeCardParser.cameraModel(in: "GFX 100S II") != nil) // not in catalog, still recorded
    }
}

@Suite("Camera connection by model")
@MainActor
struct CameraModelConnectionTests {
    func makeController() -> CameraController {
        let paths = AppPaths.temporary()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "filmlab.tests.\(UUID().uuidString)")!)
        settings.experimentalSlotWrites = true
        return CameraController(settings: settings, backupStore: CameraBackupStore(directory: paths.backups))
    }

    func attach(_ c: CameraController, model: String) async {
        let cam = SimulatedFujiCamera(model: model)
        let t = FujiPTPCameraTransport(channel: cam, kind: .demo, opensPTPSession: true, writesEnabled: { true })
        await c.attachForTesting(t)
    }

    @Test("A recognised body without slot reports is profile-only: no reads, no writes")
    func profileOnly() async {
        let c = makeController()
        await attach(c, model: "X-T4")
        guard case .profileOnly(let id) = c.state else { Issue.record("expected profileOnly, got \(c.state)"); return }
        #expect(id.model == "X-T4")
        #expect(c.transport == nil)
        #expect(!c.state.canRead && !c.state.canWrite)
        #expect(c.profile.modelName == "X-T4" && c.profile.generation == .iv)
        c.refreshWritability() // must not resurrect a writable state without a transport
        if case .profileOnly = c.state {} else { Issue.record("refreshWritability changed state to \(c.state)") }
    }

    @Test("Unknown bodies are unsupported; the X-T30 III connects")
    func unknownAndReference() async {
        let c = makeController()
        await attach(c, model: "X-A7")
        if case .unsupportedModel = c.state {} else { Issue.record("expected unsupportedModel, got \(c.state)") }
        let d = makeController()
        await attach(d, model: "X-T30 III")
        #expect(d.transport != nil)
        #expect(d.state.canRead)
        #expect(d.profile == .xt30III)
    }

    @Test("My camera setting persists and falls back to the reference body")
    func myCameraSetting() {
        let defaults = UserDefaults(suiteName: "filmlab.tests.\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        #expect(s.myCamera.id == "x-t30-iii")
        s.myCameraID = "x-t4"
        #expect(AppSettings(defaults: defaults).myProfile.modelName == "X-T4")
        defaults.set("not-a-camera", forKey: "myCameraID")
        #expect(AppSettings(defaults: defaults).myCamera.id == "x-t30-iii")
    }
}
