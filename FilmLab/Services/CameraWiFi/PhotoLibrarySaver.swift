import Foundation
#if canImport(Photos)
import Photos
#endif

/// Saves downloaded camera files into the iPhone's Photos library without re-encoding: the
/// file is handed to Photos as-is (moved, not copied), so a 12 MB JPEG costs no extra decode,
/// encode or disk copy. Asks only for add-only access.
enum PhotoLibrarySaver {
    enum SaveError: Error, LocalizedError {
        case denied
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .denied: "FilmLab can't add photos. Allow “Add Photos Only” for FilmLab in Settings › Privacy › Photos."
            case .failed(let m): "Couldn't save to Photos: \(m)"
            }
        }
    }

    static func ensureAccess() async throws {
        #if canImport(Photos)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        #endif
    }

    /// Moves `fileURL` into Photos. Returns the new asset's local identifier.
    @discardableResult
    static func save(fileURL: URL, originalFileName: String) async throws -> String? {
        #if canImport(Photos)
        nonisolated(unsafe) var identifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                options.originalFilename = originalFileName
                request.addResource(with: .photo, fileURL: fileURL, options: options)
                identifier = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
        return identifier
        #else
        return nil
        #endif
    }
}

/// Remembers which camera files were already imported, so "Import new" skips them and the
/// browser can badge them. Keyed by camera + file name + capture time (not size: while browsing
/// the camera reports a placeholder size), which survives
/// reconnects even though PTP object handles don't.
struct ImportLedger: Sendable {
    private(set) var keys: Set<String> = []
    private let file: URL?

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String].self, from: data) {
            keys = Set(saved)
        }
    }

    static func key(camera: String, fileName: String, captureDate: String) -> String {
        "\(camera)|\(fileName)|\(captureDate)"
    }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    mutating func insert(_ key: String) {
        guard keys.insert(key).inserted else { return }
        save()
    }

    private func save() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(keys.sorted()).write(to: file, options: .atomic)
    }
}
