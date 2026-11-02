import Foundation

/// Custom-setting banks C1–C7 (SELECT CUSTOM SETTING / EDIT/SAVE CUSTOM SETTING).
/// These are NOT the film simulation dial's FS1–FS3 positions — see `FilmSimulationDialSlot`.
enum CameraSlot: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case c1 = 1, c2, c3, c4, c5, c6, c7

    var id: Int { rawValue }
    var index: Int { rawValue - 1 }
    var label: String { "C\(rawValue)" }

    init?(index: Int) { self.init(rawValue: index + 1) }

    static func < (lhs: CameraSlot, rhs: CameraSlot) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// FS1–FS3 film simulation dial positions. The manual says FS RECIPE lets these register
/// image-quality items separately (and separately for stills vs movies). FilmLab models them
/// only so the UI can explain the difference; it never claims to write them.
enum FilmSimulationDialSlot: String, Codable, CaseIterable, Sendable {
    case fs1 = "FS1", fs2 = "FS2", fs3 = "FS3"
}

/// How confident we are that a capability works. Shown verbatim in the UI and docs.
enum VerificationStatus: String, Codable, Sendable, Comparable {
    case notVerified
    case reportedByThirdParty
    case verifiedInDocs
    case verifiedOnDevice

    var label: String {
        switch self {
        case .notVerified: "Not verified"
        case .reportedByThirdParty: "Reported by third party"
        case .verifiedInDocs: "Verified in Apple/Fujifilm docs"
        case .verifiedOnDevice: "Verified on a physical camera by FilmLab"
        }
    }

    private var rank: Int {
        switch self {
        case .notVerified: 0
        case .reportedByThirdParty: 1
        case .verifiedInDocs: 2
        case .verifiedOnDevice: 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Privacy-preserving identity. The serial is never stored — only a salted hash so we can
/// tell "same body as last time" for backups.
struct CameraIdentity: Codable, Equatable, Hashable, Sendable {
    var manufacturer: String
    var model: String
    var firmwareVersion: String?
    var serialHash: String?
    var isDemo: Bool

    var displayName: String { isDemo ? "\(model) (Demo)" : model }

    static let demoXT30III = CameraIdentity(
        manufacturer: "FUJIFILM", model: "X-T30 III", firmwareVersion: "demo", serialHash: nil, isDemo: true
    )
}

/// Connection lifecycle as surfaced to the user.
enum CameraConnectionState: Equatable, Sendable {
    case disconnected
    case searching
    case permissionNeeded
    case permissionDenied
    case connected(CameraIdentity)
    case wrongMode(String)
    case unsupportedModel(String)
    /// A catalog body FilmLab recognises but has no slot-access reports for: its profile is
    /// shown, but slots are neither read (reading selects a slot over PTP) nor written.
    case profileOnly(CameraIdentity)
    case readyReadOnly(CameraIdentity)
    case readyWritable(CameraIdentity)
    case busy(CameraIdentity, String)
    case failed(String)

    var identity: CameraIdentity? {
        switch self {
        case .connected(let i), .profileOnly(let i), .readyReadOnly(let i), .readyWritable(let i), .busy(let i, _): i
        default: nil
        }
    }

    var title: String {
        switch self {
        case .disconnected: "Disconnected"
        case .searching: "Searching for camera…"
        case .permissionNeeded: "Permission needed"
        case .permissionDenied: "Permission denied"
        case .connected: "Connected"
        case .wrongMode: "Wrong USB mode"
        case .unsupportedModel: "Unsupported model"
        case .profileOnly: "Recognised · Profile only"
        case .readyReadOnly: "Ready · Read-only"
        case .readyWritable: "Ready · Writes enabled"
        case .busy(_, let what): "Busy · \(what)"
        case .failed: "Connection failed"
        }
    }

    var canRead: Bool {
        switch self {
        case .readyReadOnly, .readyWritable: true
        default: false
        }
    }

    var canWrite: Bool {
        if case .readyWritable = self { return true }
        return false
    }
}

/// A raw property value preserved byte-for-byte from the camera so backups never lose data we
/// don't understand. `code` is the PTP device property code.
struct RawPropertyValue: Codable, Equatable, Hashable, Sendable {
    var code: UInt16
    var bytes: Data
}

/// Everything read from one C slot at one moment.
struct CameraSlotSnapshot: Codable, Identifiable, Equatable, Sendable {
    enum Completeness: String, Codable, Sendable {
        /// Every property FilmLab knows about was read and decoded.
        case complete
        /// Some properties failed to read or decoded to unknown values (see `unknownValues`).
        case partial
        /// Read failed.
        case failed
    }

    var id: UUID = UUID()
    var slot: CameraSlot
    var name: String
    /// Decoded settings (best-effort). `nil` if nothing decodable was read.
    var settings: RecipeSettings?
    /// Every raw property read, preserved for backup/restore.
    var rawValues: [RawPropertyValue]
    /// Codes whose values were read but not understood by `FujiRecipeCodec`.
    var unknownValues: [RawPropertyValue]
    var readAt: Date
    var camera: CameraIdentity
    var completeness: Completeness
}

/// A timestamped backup of all slots (local only; exportable as JSON).
struct CameraBackup: Codable, Identifiable, Equatable, Sendable {
    static let schemaVersion = 1
    var schemaVersion: Int = CameraBackup.schemaVersion
    var id: UUID = UUID()
    var createdAt: Date
    var camera: CameraIdentity
    var reason: String
    var snapshots: [CameraSlotSnapshot]
}
