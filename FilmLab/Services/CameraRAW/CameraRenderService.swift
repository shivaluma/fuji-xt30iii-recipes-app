import Foundation
import CoreGraphics
import ImageIO

enum CameraRenderAvailability: Equatable, Sendable {
    case available(model: String)
    case demo
    case notConnected
    /// The transport exists but the RAW-conversion protocol hasn't passed the real-device test.
    case notValidated(String)
    case incompatibleSource(String)

    var isUsable: Bool {
        switch self {
        case .available, .demo: true
        default: false
        }
    }

    var message: String {
        switch self {
        case .available(let m): "Ready to render with \(m)."
        case .demo: "Demo camera: renders are simulated with the approximate engine and labelled Demo."
        case .notConnected: "Connect an X-T30 III in USB RAW CONV./BACKUP RESTORE mode to render with the camera."
        case .notValidated(let why): why
        case .incompatibleSource(let why): why
        }
    }
}

enum CameraRenderError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case invalidJPEG
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let m): m
        case .invalidJPEG: "The camera returned data that isn't a valid JPEG. Nothing was marked Authentic."
        case .cancelled: "Camera render cancelled."
        }
    }
}

/// Camera-backed RAW → JPEG rendering. Contract: never modifies the source RAF and never
/// changes C1–C7. A result may be labelled `.authenticCamera` ONLY if a JPEG produced by the
/// camera was received and passed `AuthenticJPEGValidator`.
protocol CameraRenderService: Sendable {
    func availability(for asset: PhotoAsset?) async -> CameraRenderAvailability
    func render(asset: PhotoAsset, sourceURL: URL, settings: RecipeSettings) async throws -> RenderedPreview
}

/// Validates bytes returned by a camera before anything is labelled Authentic.
enum AuthenticJPEGValidator {
    static let maxBytes = 80 * 1024 * 1024

    static func validate(_ data: Data) throws -> CGImage {
        guard data.count > 4, data.count <= maxBytes,
              data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xD8,         // SOI
              data[data.endIndex - 2] == 0xFF, data[data.endIndex - 1] == 0xD9,         // EOI
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              (CGImageSourceGetType(src) as String?) == "public.jpeg",
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              image.width > 0, image.height > 0
        else { throw CameraRenderError.invalidJPEG }
        return image
    }
}

/// Real-hardware service. DISABLED until the protocol passes docs/device-test-matrix.md §RAW.
///
/// Community sources describe a RAW-conversion sequence (vendor ops reported by reshipi,
/// a conversion trigger property reported by both) but disagree on details, and nobody has shown
/// that it leaves C1–C7 untouched on the X-T30 III. Per our hard constraint we disable the
/// feature rather than risk silently changing a preset. See docs/ptp-validation.md.
struct UnvalidatedCameraRenderService: CameraRenderService {
    var isCameraConnected: @Sendable () async -> Bool

    func availability(for asset: PhotoAsset?) async -> CameraRenderAvailability {
        guard await isCameraConnected() else { return .notConnected }
        return .notValidated("Render with Camera is not yet validated on a real iPhone + X-T30 III, so it is disabled. FilmLab never labels a preview Authentic without a verified camera-generated JPEG.")
    }

    func render(asset: PhotoAsset, sourceURL: URL, settings: RecipeSettings) async throws -> RenderedPreview {
        throw CameraRenderError.unavailable(await availability(for: asset).message)
    }
}

/// Demo-mode camera rendering: exercises the UI flow (progress, cancellation, compare) with the
/// approximate engine, and labels output `Demo · Simulated camera` — never Authentic.
struct DemoCameraRenderService: CameraRenderService {
    let renderer: OfflinePreviewRenderer
    var simulatedLatency: Duration = .milliseconds(1200)

    func availability(for asset: PhotoAsset?) async -> CameraRenderAvailability { .demo }

    func render(asset: PhotoAsset, sourceURL: URL, settings: RecipeSettings) async throws -> RenderedPreview {
        try await Task.sleep(for: simulatedLatency)
        try await renderer.loadSource(asset: asset, url: sourceURL)
        var preview = try await renderer.render(fingerprint: asset.fingerprint, settings: settings, longEdge: 2048)
        preview.fidelity = .demoSimulatedCamera
        preview.key.fidelity = .demoSimulatedCamera
        preview.key.processingIdentity = "demo"
        preview.cameraModel = "X-T30 III (Demo)"
        return preview
    }
}
