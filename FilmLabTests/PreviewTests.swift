import Testing
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
#if !FILMLAB_CLI
@testable import FilmLab
#endif

/// Helpers for pixel inspection.
enum Pixels {
    static func rgba(_ image: CGImage, width: Int? = nil, height: Int? = nil) -> (w: Int, h: Int, data: [UInt8]) {
        let w = width ?? image.width, h = height ?? image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, buf)
    }

    static func mean(_ image: CGImage) -> SIMD3<Double> {
        let (w, h, d) = rgba(image, width: 32, height: 32)
        var s = SIMD3<Double>.zero
        for i in 0..<(w * h) { s += SIMD3(Double(d[i * 4]), Double(d[i * 4 + 1]), Double(d[i * 4 + 2])) }
        return s / Double(w * h)
    }

    /// Mean absolute per-channel difference (0–255). `fullResolution` keeps fine detail (grain).
    static func difference(_ a: CGImage, _ b: CGImage, fullResolution: Bool = false) -> Double {
        let (w, h, da) = fullResolution ? rgba(a) : rgba(a, width: 48, height: 32)
        let (_, _, db) = fullResolution ? rgba(b, width: w, height: h) : rgba(b, width: 48, height: 32)
        var total = 0.0
        for i in 0..<(w * h * 4) where i % 4 != 3 { total += abs(Double(da[i]) - Double(db[i])) }
        return total / Double(w * h * 3)
    }
}

@Suite("Offline preview engine")
struct PreviewEngineTests {
    func renderer() async throws -> OfflinePreviewRenderer {
        let r = OfflinePreviewRenderer(diskCacheDirectory: nil, outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let data = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[0], size: CGSize(width: 600, height: 400)))
        let image = try #require(CIImage(data: data, options: [.applyOrientationProperty: true]))
        await r.register(source: image, fingerprint: "landscape")
        return r
    }

    @Test("Every film simulation produces a visibly different image")
    func simulationsDiffer() async throws {
        let r = try await renderer()
        let original = try await r.renderOriginal(fingerprint: "landscape", longEdge: 300).image
        var images: [FilmSimulation: CGImage] = [:]
        for sim in FilmSimulation.allCases {
            images[sim] = try await r.render(fingerprint: "landscape", settings: .neutral(sim), longEdge: 300).image
        }
        for sim in FilmSimulation.allCases where sim != .provia {
            #expect(Pixels.difference(images[sim]!, original) > 1.0, "\(sim) ≈ original")
        }
        let distinct: [(FilmSimulation, FilmSimulation)] = [(.provia, .velvia), (.provia, .classicChrome), (.classicNeg, .nostalgicNeg),
                                                            (.eterna, .eternaBleachBypass), (.acros, .acrosR), (.acros, .sepia), (.proNegHi, .proNegStd)]
        for (a, b) in distinct {
            #expect(Pixels.difference(images[a]!, images[b]!) > 1.0, "\(a) ≈ \(b)")
        }
    }

    @Test("Monochrome simulations output neutral greys; Sepia is toned")
    func monochrome() async throws {
        let r = try await renderer()
        let (w, h, d) = Pixels.rgba(try await r.render(fingerprint: "landscape", settings: .neutral(.acros), longEdge: 300).image, width: 40, height: 30)
        var maxSpread = 0
        for i in 0..<(w * h) {
            let px = [Int(d[i * 4]), Int(d[i * 4 + 1]), Int(d[i * 4 + 2])]
            maxSpread = max(maxSpread, px.max()! - px.min()!)
        }
        #expect(maxSpread <= 3)
        let sepia = Pixels.mean(try await r.render(fingerprint: "landscape", settings: .neutral(.sepia), longEdge: 300).image)
        #expect(sepia.x > sepia.z + 8)
    }

    @Test("Adjustments move pixels in the expected direction")
    func directions() async throws {
        let r = try await renderer()
        func mean(_ s: RecipeSettings) async throws -> SIMD3<Double> {
            Pixels.mean(try await r.render(fingerprint: "landscape", settings: s, longEdge: 200).image)
        }
        let base = try await mean(.neutral(.provia))
        var warm = RecipeSettings.neutral(.provia); warm.whiteBalance = .value(.colorTemperature); warm.kelvin = .value(9000)
        var cool = warm; cool.kelvin = .value(3000)
        let w = try await mean(warm), c = try await mean(cool)
        #expect(w.x - w.z > base.x - base.z)   // higher Kelvin setting renders warmer
        #expect(c.z - c.x > base.z - base.x)   // lower renders cooler
        var bright = RecipeSettings.neutral(.provia); bright.suggestedExposureCompensation = .value(1)
        #expect(try await mean(bright).y > base.y + 5)
        var red = RecipeSettings.neutral(.provia); red.wbShiftRed = .value(9)
        #expect(try await mean(red).x > base.x + 3)
    }

    @Test("Grain is deterministic and visible")
    func grain() async throws {
        let r = try await renderer()
        var s = RecipeSettings.neutral(.provia); s.grainRoughness = .value(.strong); s.grainSize = .value(.large)
        let a = try await r.render(fingerprint: "landscape", settings: s, longEdge: 300).image
        await r.clearCaches(includingDisk: false)
        let b = try await r.render(fingerprint: "landscape", settings: s, longEdge: 300).image
        let none = try await r.render(fingerprint: "landscape", settings: .neutral(.provia), longEdge: 300).image
        #expect(Pixels.difference(a, b, fullResolution: true) < 0.01)
        #expect(Pixels.difference(a, none, fullResolution: true) > 0.5)
    }

    @Test("Rendering never accumulates: same settings → same pixels regardless of history")
    func noAccumulation() async throws {
        let r = try await renderer()
        let target = RecipeSettings.neutral(.classicChrome)
        let first = try await r.render(fingerprint: "landscape", settings: target, longEdge: 240).image
        for sim in [FilmSimulation.velvia, .acros, .eterna] { _ = try await r.render(fingerprint: "landscape", settings: .neutral(sim), longEdge: 240) }
        await r.clearCaches(includingDisk: false)
        let again = try await r.render(fingerprint: "landscape", settings: target, longEdge: 240).image
        #expect(Pixels.difference(first, again) < 0.01)
    }

    @Test("Cache keys cover source, settings, engine, size and colour space")
    func cacheKeys() async throws {
        let r = try await renderer()
        let a = r.cacheKey(fingerprint: "landscape", settings: .neutral(.provia), longEdge: 300)
        #expect(a.engineVersion == FilmLookEngine.version)
        #expect(a.colorSpace.uppercased().contains("SRGB"))
        #expect(a != (r.cacheKey(fingerprint: "other", settings: .neutral(.provia), longEdge: 300)))
        #expect(a != (r.cacheKey(fingerprint: "landscape", settings: .neutral(.velvia), longEdge: 300)))
        #expect(a != (r.cacheKey(fingerprint: "landscape", settings: .neutral(.provia), longEdge: 301)))
        let p3 = OfflinePreviewRenderer(diskCacheDirectory: nil)
        #expect(a.colorSpace != (p3.cacheKey(fingerprint: "landscape", settings: .neutral(.provia), longEdge: 300)).colorSpace)
        _ = try await r.render(fingerprint: "landscape", settings: .neutral(.provia), longEdge: 300)
        let count = await r.renderCount
        _ = try await r.render(fingerprint: "landscape", settings: .neutral(.provia), longEdge: 300)
        #expect(await r.renderCount == count) // memory hit
    }

    @Test("Disk cache hits, invalidates per source, and LRU evicts oldest")
    func diskAndLRU() async throws {
        let dir = AppPaths.temporary().previewCache
        let r = OfflinePreviewRenderer(diskCacheDirectory: dir, outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let data = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[1], size: CGSize(width: 300, height: 200)))
        await r.register(source: try #require(CIImage(data: data)), fingerprint: "chart")
        _ = try await r.render(fingerprint: "chart", settings: .neutral(.astia), longEdge: 200)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        await r.clearCaches(includingDisk: false)
        let before = await r.renderCount
        _ = try await r.render(fingerprint: "chart", settings: .neutral(.astia), longEdge: 200)
        #expect(await r.renderCount == before) // disk hit
        await r.unregister(fingerprint: "chart")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)

        var lru = LRUCache<Int, String>(capacity: 2)
        lru.insert("a", for: 1); lru.insert("b", for: 2)
        _ = lru.value(for: 1)
        lru.insert("c", for: 3)
        #expect(lru.value(for: 2) == nil)
        #expect(lru.value(for: 1) == "a")
        #expect(lru.count == 2)
    }

    @Test("EXIF orientation is honoured and the original file is never modified")
    func orientation() async throws {
        // Build a 300×200 JPEG tagged orientation 6 (rotate 90° CW for display).
        let base = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[0], size: CGSize(width: 300, height: 200)))
        let src = try #require(CGImageSourceCreateWithData(base as CFData, nil))
        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(dest, src, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let paths = AppPaths.temporary()
        let importer = PhotoImporter(paths: paths)
        let asset = try importer.importData(out as Data, fileName: "rot.jpg", typeHint: .jpeg, source: .files)
        #expect(asset.exifOrientation == 6)
        let url = importer.url(for: asset)
        let originalBytes = try Data(contentsOf: url)
        let r = OfflinePreviewRenderer(diskCacheDirectory: nil)
        try await r.loadSource(asset: asset, url: url)
        let img = try await r.render(fingerprint: asset.fingerprint, settings: .neutral(.velvia), longEdge: 300).image
        #expect(img.height > img.width) // displayed upright (portrait)
        #expect(try Data(contentsOf: url) == originalBytes)
    }

    @Test("Unsupported RAW data fails clearly instead of showing an embedded JPEG")
    func badRAW() async throws {
        let paths = AppPaths.temporary()
        try paths.createDirectories()
        let url = paths.originals.appendingPathComponent("fake.raf")
        try Data("FUJIFILMCCD-RAW not really".utf8).write(to: url)
        #expect(throws: PreviewError.self) { _ = try SourceImageLoader.load(url: url, isRAW: true) }
    }

    @Test("Histogram is computed from rendered pixels")
    func histogram() throws {
        let data = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[1], size: CGSize(width: 120, height: 80)))
        let img = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let h = try #require(Histogram.compute(from: img))
        #expect(h.luma.count == Histogram.bins)
        #expect(h.luma.max() == 1 || h.red.max() == 1 || h.green.max() == 1 || h.blue.max() == 1)
    }

    @Test("LUT transform keeps neutral greys neutral for colour sims without tints")
    func lutNeutral() {
        let key = FilmLUTKey(settings: .neutral(.provia))
        for v in stride(from: Float(0.05), through: 0.95, by: 0.1) {
            let o = FilmLUTBuilder.transform(SIMD3(repeating: v), key: key)
            #expect(abs(o.x - o.y) < 0.002 && abs(o.y - o.z) < 0.002)
        }
        // Tone curve is monotonic.
        var last: Float = -1
        for v in stride(from: Float(0), through: 1, by: 0.02) {
            let o = FilmLUTBuilder.transform(SIMD3(repeating: v), key: key).y
            #expect(o >= last - 1e-5); last = o
        }
    }
}

@Suite("Golden image regression")
struct GoldenImageTests {
    struct Golden: Codable { var engine: String; var means: [String: [Double]] }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/golden-\(FilmLookEngine.version).json")
    }

    /// Mean colour of the synthetic chart per simulation, ±3/255 tolerance.
    /// Record with: FILMLAB_RECORD_GOLDEN=1 ./scripts/test-cli.sh
    @Test("Chart renders match the recorded golden values")
    func golden() async throws {
        let r = OfflinePreviewRenderer(diskCacheDirectory: nil, outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let data = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[1], size: CGSize(width: 480, height: 320)))
        await r.register(source: try #require(CIImage(data: data)), fingerprint: "golden")
        var means: [String: [Double]] = [:]
        for sim in FilmSimulation.allCases {
            let m = Pixels.mean(try await r.render(fingerprint: "golden", settings: .neutral(sim), longEdge: 240).image)
            means[sim.rawValue] = [m.x, m.y, m.z].map { ($0 * 10).rounded() / 10 }
        }
        if ProcessInfo.processInfo.environment["FILMLAB_RECORD_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: Self.fixtureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(Golden(engine: FilmLookEngine.version, means: means)).write(to: Self.fixtureURL)
            return
        }
        guard let fixture = try? JSONDecoder().decode(Golden.self, from: Data(contentsOf: Self.fixtureURL)) else {
            Issue.record("Missing golden fixture at \(Self.fixtureURL.path). Record it with FILMLAB_RECORD_GOLDEN=1.")
            return
        }
        for (sim, expected) in fixture.means {
            let got = try #require(means[sim])
            let delta = zip(expected, got).map { abs($0 - $1) }.max() ?? 0
            #expect(delta <= 3.0, "\(sim): expected \(expected) got \(got) (Δ \(delta))")
        }
    }
}

@Suite("Studio model")
@MainActor
struct StudioModelTests {
    func makeStudio() async throws -> StudioModel {
        let library = LibraryStore(paths: .temporary())
        library.ensureDemoAssets()
        library.webRecipes = TestRecipes.all        // stands in for the website's catalogue
        let renderer = OfflinePreviewRenderer(diskCacheDirectory: nil)
        let studio = StudioModel(renderer: renderer, library: library, cameraRenderService: UnvalidatedCameraRenderService(isCameraConnected: { false }))
        await studio.select(try #require(library.assets.first))
        await studio.waitForRender()
        return studio
    }

    @Test("Choosing a photo and tapping simulations visibly changes the preview")
    func verticalSlice() async throws {
        let studio = try await makeStudio()
        let original = try #require(studio.original?.image)
        studio.setFilmSimulation(.velvia)
        await studio.waitForRender()
        let velvia = try #require(studio.preview)
        studio.setFilmSimulation(.acros)
        await studio.waitForRender()
        let acros = try #require(studio.preview)
        #expect(velvia.fidelity == .approximateOnDevice)
        #expect(Pixels.difference(velvia.image, acros.image) > 2)
        #expect(Pixels.difference(velvia.image, original) > 1)
        #expect(studio.histogram != nil)
    }

    @Test("Rapid slider changes never leave a stale frame on screen")
    func noStaleFrames() async throws {
        let studio = try await makeStudio()
        for i in 0..<25 {
            studio.recipe.settings.shadow = .value(Double(i % 9) * 0.5 - 2)
            studio.recipe.settings.highlight = .value(Double(i % 5) * 0.5)
            if i % 4 == 0 { try await Task.sleep(for: .milliseconds(5)) }
        }
        await studio.waitForRender()
        #expect(studio.preview?.key.settingsFingerprint == studio.recipe.settings.fingerprint)
        #expect(!studio.isRendering)
    }

    @Test("Compare grid renders each recipe on the same photo at the same size")
    func compare() async throws {
        let studio = try await makeStudio()
        let ids = Array(TestRecipes.all.prefix(4).map(\.id))
        studio.setCompare(ids)
        studio.setCompare(Array(ids.prefix(2)))   // supersede: obsolete request cancelled
        await studio.waitForCompare()
        #expect(Set(studio.compareResults.keys) == Set(ids.prefix(2)))
        let sizes = Set(studio.compareResults.values.map { "\($0.image.width)x\($0.image.height)" })
        #expect(sizes.count == 1)
    }

    @Test("Save as new recipe persists and works offline")
    func save() async throws {
        let studio = try await makeStudio()
        studio.load(TestRecipes.all[2])
        studio.recipe.settings.color = .value(3)
        #expect(studio.isDirty)
        #expect(!studio.canSaveInPlace) // not in the library: nothing to overwrite
        let saved = studio.saveAsNew(name: "My Kitchen")
        #expect(!studio.isDirty)
        #expect(saved.provenance.derivedFrom == TestRecipes.all[2].id)
        let reloaded = LibraryStore(paths: studio.library.paths)
        #expect(reloaded.recipes.first { $0.id == saved.id }?.settings.color == .value(3))
        #expect(studio.canSaveInPlace)
    }

    @Test("Render with Camera is unavailable without a validated camera")
    func cameraUnavailable() async throws {
        let studio = try await makeStudio()
        await studio.refreshCameraAvailability()
        #expect(!studio.cameraAvailability.isUsable)
        studio.renderWithCamera()
        try await Task.sleep(for: .milliseconds(50))
        if case .failed = studio.cameraRenderState {} else { Issue.record("expected failure state") }
        #expect(studio.cameraPreview == nil)
    }
}
