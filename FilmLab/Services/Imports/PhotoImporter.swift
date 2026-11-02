import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

enum ImportError: Error, LocalizedError, Equatable {
    case unreadable
    case tooLarge(Int)
    case unsupportedType(String)
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file couldn't be read as a photo."
        case .tooLarge(let mb): "This file is \(mb) MB; FilmLab accepts photos up to 250 MB."
        case .unsupportedType(let t): "“\(t)” isn't a supported photo type. Use JPEG, HEIF, PNG or a supported RAW file."
        case .accessDenied: "FilmLab wasn't given access to that file."
        }
    }
}

/// Copies picked photos into the app container (immutable originals) and extracts metadata.
/// The user's original in Photos/Files is never touched.
struct PhotoImporter: Sendable {
    let paths: AppPaths
    static let maxBytes = 250 * 1024 * 1024
    static let rafType = UTType(filenameExtension: "raf", conformingTo: .rawImage)

    func url(for asset: PhotoAsset) -> URL {
        paths.originals.appendingPathComponent(asset.storedFileName)
    }

    /// Imports a file picked from Files. Handles security-scoped access correctly.
    func importFile(at url: URL, source: PhotoAsset.Source = .files) throws -> PhotoAsset {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.mappedIfSafe]) } catch { throw ImportError.accessDenied }
        return try importData(data, fileName: url.lastPathComponent,
                              typeHint: UTType(filenameExtension: url.pathExtension), source: source)
    }

    func importData(_ data: Data, fileName: String?, typeHint: UTType?, source: PhotoAsset.Source, note: String? = nil) throws -> PhotoAsset {
        guard data.count <= Self.maxBytes else { throw ImportError.tooLarge(data.count / 1_048_576) }
        let fingerprint = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()

        let src = CGImageSourceCreateWithData(data as CFData, nil)
        let detectedType = src.flatMap { CGImageSourceGetType($0) as String? }.flatMap(UTType.init)
        let type = detectedType ?? typeHint
        guard let type else { throw ImportError.unreadable }
        let isRAW = type.conforms(to: .rawImage) || typeHint?.conforms(to: .rawImage) == true
        guard isRAW || type.conforms(to: .image) else { throw ImportError.unsupportedType(type.identifier) }

        let props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        if !isRAW, width == 0 || height == 0 { throw ImportError.unreadable }

        let id = UUID()
        let ext = type.preferredFilenameExtension ?? (fileName as NSString?)?.pathExtension ?? "img"
        let stored = "\(id.uuidString).\(ext)"
        try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
        let dest = paths.originals.appendingPathComponent(stored)
        try data.write(to: dest, options: [.atomic, .completeFileProtectionUnlessOpen])
        // Mark read-only: FilmLab never writes to an original after import.
        try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dest.path)

        return PhotoAsset(
            id: id, source: source, storedFileName: stored, originalFileName: fileName,
            typeIdentifier: type.identifier, isRAW: isRAW, fingerprint: fingerprint,
            pixelWidth: width, pixelHeight: height,
            exifOrientation: props[kCGImagePropertyOrientation] as? Int ?? 1,
            colorProfileName: props[kCGImagePropertyProfileName] as? String,
            cameraMake: (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces),
            cameraModel: (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces),
            captureDate: (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.parseEXIFDate),
            importedAt: Date(), note: note)
    }

    func delete(_ asset: PhotoAsset) {
        let u = url(for: asset)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: u.path)
        try? FileManager.default.removeItem(at: u)
    }

    static func parseEXIFDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: s)
    }
}
