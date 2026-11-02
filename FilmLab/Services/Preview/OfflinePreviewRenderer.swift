import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

enum PreviewError: Error, LocalizedError, Equatable {
    case sourceNotLoaded
    case unreadableImage(String)
    case rawNotSupported(String)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .sourceNotLoaded: "The photo isn't loaded yet."
        case .unreadableImage(let n): "Couldn't read “\(n)” as an image."
        case .rawNotSupported(let detail):
            "This RAW file can't be decoded on this device (\(detail)). Export a JPEG from the camera or another app and import that instead."
        case .renderFailed: "Rendering failed."
        }
    }
}

/// Loads originals into oriented, colour-managed Core Image sources. Never modifies files.
enum SourceImageLoader {
    static func load(url: URL, isRAW: Bool) throws -> CIImage {
        if isRAW {
            // CIRAWFilter returns nil when the camera/codec isn't supported on this OS. We never
            // fall back to the embedded JPEG and present it as a RAW render.
            guard let raw = CIRAWFilter(imageURL: url), raw.nativeSize.width > 0, raw.nativeSize.height > 0,
                  let image = raw.outputImage, !image.extent.isInfinite, !image.extent.isEmpty else {
                throw PreviewError.rawNotSupported("Core Image RAW decoder unavailable for this file")
            }
            return image
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw PreviewError.unreadableImage(url.lastPathComponent)
        }
        return image
    }

    /// Lanczos downscale so the long edge is at most `longEdge` (never upscales).
    static func scaled(_ image: CIImage, longEdge: Int) -> CIImage {
        let extent = image.extent
        let current = max(extent.width, extent.height)
        guard current > CGFloat(longEdge), current > 0 else { return image }
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = image
        f.scale = Float(CGFloat(longEdge) / current)
        f.aspectRatio = 1
        guard let out = f.outputImage else { return image }
        return out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
    }
}

/// Approximate on-device renderer with memory + disk caches.
///
/// Thread-safety: an actor; Core Image work runs on its executor (off the main thread).
/// Callers implement stale-frame protection with generation tokens (see `StudioModel`).
actor OfflinePreviewRenderer {
    private let engine: FilmLookEngine
    private let context: CIContext
    private let outputColorSpace: CGColorSpace
    private let diskCache: DiskPreviewCache?
    private var sources: [String: CIImage] = [:]          // fingerprint → full-size oriented source
    private var workingCopies = LRUCache<String, CIImage>(capacity: 12) // "fp@edge" → bitmap-backed
    private var memoryCache = LRUCache<RenderCacheKey, CGImage>(capacity: 80)
    private(set) var renderCount = 0

    init(engine: FilmLookEngine = FilmLookEngine(), diskCacheDirectory: URL? = nil,
         outputColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!) {
        self.engine = engine
        self.outputColorSpace = outputColorSpace
        self.context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
            .name: "FilmLab.preview",
        ])
        self.diskCache = diskCacheDirectory.map(DiskPreviewCache.init(directory:))
    }

    nonisolated var colorSpaceName: String { (outputColorSpace.name as String?) ?? "unknown" }

    func hasSource(_ fingerprint: String) -> Bool { sources[fingerprint] != nil }

    func register(source: CIImage, fingerprint: String) {
        sources[fingerprint] = source
        workingCopies.removeAll { $0.hasPrefix(fingerprint + "@") }
    }

    func loadSource(asset: PhotoAsset, url: URL) throws {
        guard sources[asset.fingerprint] == nil else { return }
        register(source: try SourceImageLoader.load(url: url, isRAW: asset.isRAW), fingerprint: asset.fingerprint)
    }

    func unregister(fingerprint: String) {
        sources.removeValue(forKey: fingerprint)
        workingCopies.removeAll { $0.hasPrefix(fingerprint + "@") }
        memoryCache.removeAll { $0.sourceFingerprint == fingerprint }
        diskCache?.invalidate(sourceFingerprint: fingerprint)
    }

    nonisolated func cacheKey(fingerprint: String, settings: RecipeSettings?, longEdge: Int) -> RenderCacheKey {
        RenderCacheKey(sourceFingerprint: fingerprint,
                       settingsFingerprint: settings?.fingerprint ?? "original",
                       engineVersion: FilmLookEngine.version,
                       longEdge: longEdge,
                       colorSpace: colorSpaceName,
                       fidelity: .approximateOnDevice)
    }

    /// Bitmap-backed working copy at the requested size, so slider renders don't re-decode
    /// or re-resample the original.
    private func workingCopy(_ fingerprint: String, longEdge: Int) throws -> CIImage {
        let key = "\(fingerprint)@\(longEdge)"
        if let hit = workingCopies.value(for: key) { return hit }
        guard let source = sources[fingerprint] else { throw PreviewError.sourceNotLoaded }
        let scaled = SourceImageLoader.scaled(source, longEdge: longEdge)
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        guard let cg = context.createCGImage(scaled, from: scaled.extent, format: .RGBAh, colorSpace: linear) else {
            throw PreviewError.renderFailed
        }
        let image = CIImage(cgImage: cg)
        workingCopies.insert(image, for: key)
        return image
    }

    /// Renders the untouched original at the given size (the "Original" side of before/after).
    func renderOriginal(fingerprint: String, longEdge: Int) throws -> RenderedPreview {
        try render(fingerprint: fingerprint, settings: nil, longEdge: longEdge)
    }

    /// Renders `settings` on the source. `settings == nil` → original.
    func render(fingerprint: String, settings: RecipeSettings?, longEdge: Int) throws -> RenderedPreview {
        let key = cacheKey(fingerprint: fingerprint, settings: settings, longEdge: longEdge)
        if let hit = memoryCache.value(for: key) {
            return RenderedPreview(image: hit, fidelity: .approximateOnDevice, key: key, renderMilliseconds: 0)
        }
        if let disk = diskCache?.read(key) {
            memoryCache.insert(disk, for: key)
            return RenderedPreview(image: disk, fidelity: .approximateOnDevice, key: key, renderMilliseconds: 0)
        }
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let base = try workingCopy(fingerprint, longEdge: longEdge)
        let output = settings.map { engine.apply($0, to: base) } ?? base
        try Task.checkCancellation()
        guard let cg = context.createCGImage(output, from: base.extent, format: .RGBA8, colorSpace: outputColorSpace) else {
            throw PreviewError.renderFailed
        }
        renderCount += 1
        memoryCache.insert(cg, for: key)
        // Only small renders go to disk (thumbnails / compare grid).
        if longEdge <= 800 { diskCache?.write(cg, for: key) }
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        return RenderedPreview(image: cg, fidelity: .approximateOnDevice, key: key, renderMilliseconds: ms)
    }

    /// Full-resolution export of an approximate preview (JPEG data with sRGB/P3 profile embedded).
    func exportJPEG(fingerprint: String, settings: RecipeSettings, quality: Double = 0.92) throws -> Data {
        guard let source = sources[fingerprint] else { throw PreviewError.sourceNotLoaded }
        let output = engine.apply(settings, to: source)
        guard let data = context.jpegRepresentation(of: output, colorSpace: outputColorSpace,
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]) else {
            throw PreviewError.renderFailed
        }
        return data
    }

    func clearCaches(includingDisk: Bool) {
        memoryCache.removeAll()
        workingCopies.removeAll()
        if includingDisk { diskCache?.removeAll() }
    }
}
