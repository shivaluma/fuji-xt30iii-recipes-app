import Foundation
import CoreGraphics

/// How a preview was produced. Shown on every rendered image.
enum PreviewFidelity: String, Codable, Sendable {
    /// FilmLab's own Core Image approximation. Never pixel-accurate.
    case approximateOnDevice
    /// Demo mode: the simulated camera "rendered" it using the approximate engine.
    case demoSimulatedCamera
    /// A JPEG actually produced by the connected camera's processor and validated by FilmLab.
    case authenticCamera

    func badge(model: String? = nil) -> String {
        switch self {
        case .approximateOnDevice: "Approximate · On-device"
        case .demoSimulatedCamera: "Demo · Simulated camera"
        case .authenticCamera: "Authentic · \(model ?? "Camera")"
        }
    }
}

/// An imported photo. The original file is copied into the app container and never modified.
struct PhotoAsset: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case photos, files, demo }

    var id: UUID
    var source: Source
    /// File name inside the originals directory (the immutable copy).
    var storedFileName: String
    var originalFileName: String?
    /// UTType identifier, e.g. public.jpeg, public.heic, com.fuji.raw-image.
    var typeIdentifier: String
    var isRAW: Bool
    /// SHA-256 (hex prefix) of the original bytes — used for caching and duplicate detection.
    var fingerprint: String
    var pixelWidth: Int
    var pixelHeight: Int
    /// EXIF orientation 1…8 as stored in the file (the original is never rotated on disk).
    var exifOrientation: Int
    var colorProfileName: String?
    var cameraMake: String?
    var cameraModel: String?
    var captureDate: Date?
    var importedAt: Date
    /// User-visible note, e.g. "FilmLab synthetic test image".
    var note: String?

    /// "As Shot" only when the base render comes from the camera itself; FilmLab's base for any
    /// phone-decoded image is the "Original".
    var baseLabel: String { isRAW ? "Original (Apple RAW decode)" : "Original" }

    var isFujifilm: Bool { cameraMake?.uppercased().contains("FUJIFILM") ?? false }
}

/// Cache key: source fingerprint + full settings hash + engine version + size + colour space.
struct RenderCacheKey: Hashable, Sendable, CustomStringConvertible {
    var sourceFingerprint: String
    var settingsFingerprint: String
    var engineVersion: String
    var longEdge: Int
    var colorSpace: String
    var fidelity: PreviewFidelity
    /// Camera identity for authentic renders (model + firmware), empty otherwise.
    var processingIdentity: String = ""

    var description: String {
        [sourceFingerprint, settingsFingerprint, engineVersion, String(longEdge), colorSpace, fidelity.rawValue, processingIdentity]
            .joined(separator: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

/// A rendered preview held in memory.
struct RenderedPreview: Sendable {
    var image: CGImage
    var fidelity: PreviewFidelity
    var key: RenderCacheKey
    var renderMilliseconds: Int
    var cameraModel: String?
}
