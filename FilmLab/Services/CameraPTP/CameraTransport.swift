import Foundation
import CryptoKit

enum CameraTransportKind: String, Sendable {
    case demo
    case imageCaptureUSB
}

enum CameraError: Error, Equatable, LocalizedError, Sendable {
    case notConnected
    case wrongMode(String)
    case unsupportedModel(String)
    case writesDisabled
    case permissionDenied
    case busy
    case invalidSlotName(String)
    case encoding(String)
    /// The write may or may not have happened (e.g. disconnect mid-write). Re-read required.
    case outcomeUnknown(CameraSlot, String)
    case ptp(PTPError)

    var errorDescription: String? {
        switch self {
        case .notConnected: "No camera is connected."
        case .wrongMode(let m): "The camera isn't in the expected USB mode. \(m)"
        case .unsupportedModel(let m): "\(m) isn't supported yet."
        case .writesDisabled: "Writing to the camera is disabled. Enable experimental slot writes in Settings after reading the warning."
        case .permissionDenied: "FilmLab doesn't have permission to control the camera. Allow access in Settings."
        case .busy: "The camera is busy. Wait a moment and retry."
        case .invalidSlotName(let m): m
        case .encoding(let m): m
        case .outcomeUnknown(let slot, let m): "Outcome unknown for \(slot.label): \(m) Reconnect and re-read \(slot.label) to verify the camera state."
        case .ptp(let e): e.errorDescription
        }
    }
}

struct PropertyMismatch: Equatable, Sendable, Identifiable {
    var property: FujiPresetProperty
    var expected: Data
    var actual: Data?
    var id: UInt16 { property.rawValue }

    var description: String {
        "\(property) (\(property.hex)): expected \(expected.hexString), read \(actual?.hexString ?? "nothing")"
    }
}

struct SlotWriteReport: Sendable {
    enum Outcome: Equatable, Sendable { case verified, mismatched }
    var slot: CameraSlot
    var after: CameraSlotSnapshot
    var mismatches: [PropertyMismatch]
    var outcome: Outcome { mismatches.isEmpty ? .verified : .mismatched }
}

/// Camera-facing operations used by the app. Writes always require an explicit call with an
/// explicit slot; there is no "apply" or "sync" operation.
protocol CameraTransport: AnyObject, Sendable {
    var kind: CameraTransportKind { get }
    func connect() async throws -> CameraIdentity
    func readSlots(_ slots: [CameraSlot]) async throws -> [CameraSlotSnapshot]
    func writeSlot(_ slot: CameraSlot, settings: RecipeSettings, name: String) async throws -> SlotWriteReport
    func diagnosticsLog() async -> [String]
    func disconnect() async
}

/// Fujifilm preset read/write over any `PTPCommandChannel`.
actor FujiPTPCameraTransport: CameraTransport {
    nonisolated let kind: CameraTransportKind
    private let session: PTPSession
    private let operationGate = AsyncSerialGate()
    private let writesEnabled: @Sendable () -> Bool
    /// ImageCaptureCore opens the PTP session itself (`requestOpenSession`), so the USB transport
    /// must not send OpenSession through pass-through. The simulator needs it explicitly.
    private let opensPTPSession: Bool
    private var identity: CameraIdentity?
    private var deviceInfo: PTPDeviceInfo?
    /// ILF: wait ~100 ms after selecting a slot before reading.
    var slotSelectDelay: Duration = .milliseconds(100)

    init(channel: PTPCommandChannel, kind: CameraTransportKind, opensPTPSession: Bool,
         writesEnabled: @escaping @Sendable () -> Bool) {
        self.session = PTPSession(channel: channel)
        self.kind = kind
        self.opensPTPSession = opensPTPSession
        self.writesEnabled = writesEnabled
    }

    func connect() async throws -> CameraIdentity {
        do {
            if opensPTPSession { try await session.open() }
            let info = try await session.deviceInfo()
            deviceInfo = info
            guard info.manufacturer.uppercased().contains("FUJIFILM") else {
                throw CameraError.unsupportedModel(info.manufacturer + " " + info.model)
            }
            guard info.devicePropertiesSupported.contains(FujiPresetProperty.slotSelector.rawValue) else {
                throw CameraError.wrongMode("Set CONNECTION MODE to USB RAW CONV./BACKUP RESTORE and reconnect.")
            }
            let id = CameraIdentity(
                manufacturer: "FUJIFILM",
                model: info.model.trimmingCharacters(in: .whitespaces),
                firmwareVersion: info.deviceVersion,
                serialHash: Self.hashSerial(info.serialNumber),
                isDemo: kind == .demo)
            identity = id
            return id
        } catch let e as PTPError {
            throw CameraError.ptp(e)
        }
    }

    static func hashSerial(_ serial: String) -> String? {
        guard !serial.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(("filmlab.v1:" + serial).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func requireIdentity() throws -> CameraIdentity {
        guard let identity else { throw CameraError.notConnected }
        return identity
    }

    // MARK: Read

    func readSlots(_ slots: [CameraSlot]) async throws -> [CameraSlotSnapshot] {
        let camera = try requireIdentity()
        return try await exclusive { try await self.readSlotsLocked(slots, camera: camera) }
    }

    /// Runs `body` while holding the operation gate so multi-transaction operations (select slot
    /// → read/write properties) never interleave.
    private func exclusive<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        await operationGate.acquire()
        do {
            let value = try await body()
            await operationGate.release()
            return value
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func readSlotsLocked(_ slots: [CameraSlot], camera: CameraIdentity) async throws -> [CameraSlotSnapshot] {
        let original = try? await session.getPropertyValue(FujiPresetProperty.slotSelector.rawValue)
        var result: [CameraSlotSnapshot] = []
        do {
            for slot in slots {
                try Task.checkCancellation()
                result.append(try await readSlotLocked(slot, camera: camera))
            }
        } catch {
            if let original { try? await session.setPropertyValue(FujiPresetProperty.slotSelector.rawValue, original) }
            throw Self.map(error)
        }
        // reshipi restores the originally selected slot after reading.
        if let original { try? await session.setPropertyValue(FujiPresetProperty.slotSelector.rawValue, original) }
        return result
    }

    private func readSlotLocked(_ slot: CameraSlot, camera: CameraIdentity) async throws -> CameraSlotSnapshot {
        try await session.setPropertyValue(FujiPresetProperty.slotSelector.rawValue, FujiRecipeCodec.u16(UInt16(slot.rawValue)))
        try await Task.sleep(for: slotSelectDelay)
        var values: [UInt16: Data] = [:]
        var failures = 0
        for p in FujiPresetProperty.slotReadOrder {
            do {
                values[p.rawValue] = try await session.getPropertyValue(p.rawValue)
            } catch PTPError.response {
                failures += 1 // property not readable on this body — record as incomplete, keep going
            }
        }
        let decoded = FujiRecipeCodec.decode(values)
        let raw = values.sorted { $0.key < $1.key }.map { RawPropertyValue(code: $0.key, bytes: $0.value) }
        let completeness: CameraSlotSnapshot.Completeness =
            decoded.settings == nil ? .failed : (failures > 0 ? .partial : .complete)
        return CameraSlotSnapshot(slot: slot, name: decoded.name ?? slot.label, settings: decoded.settings,
                                  rawValues: raw, unknownValues: decoded.unknown, readAt: Date(),
                                  camera: camera, completeness: completeness)
    }

    // MARK: Write

    func writeSlot(_ slot: CameraSlot, settings: RecipeSettings, name: String) async throws -> SlotWriteReport {
        let camera = try requireIdentity()
        guard writesEnabled() else { throw CameraError.writesDisabled }
        let plan: [FujiRecipeCodec.EncodedProperty]
        do {
            plan = try FujiRecipeCodec.encode(settings, name: name)
        } catch let e as FujiRecipeCodec.CodecError {
            throw CameraError.encoding(e.errorDescription ?? "Encoding failed")
        }
        return try await exclusive { try await self.writeSlotLocked(slot, plan: plan, camera: camera) }
    }

    private func writeSlotLocked(_ slot: CameraSlot, plan: [FujiRecipeCodec.EncodedProperty], camera: CameraIdentity) async throws -> SlotWriteReport {
        var started = false
        do {
            try await session.setPropertyValue(FujiPresetProperty.slotSelector.rawValue, FujiRecipeCodec.u16(UInt16(slot.rawValue)))
            try await Task.sleep(for: slotSelectDelay)
            for item in plan {
                // Once the first property write is sent, cancellation can no longer guarantee
                // a clean state; we finish and verify rather than leave a half-written slot.
                if !started { try Task.checkCancellation() }
                started = true
                try await session.setPropertyValue(item.property.rawValue, item.bytes)
            }
        } catch {
            if started {
                throw CameraError.outcomeUnknown(slot, "Writing stopped part-way (\(Self.map(error).localizedDescription)).")
            }
            throw Self.map(error)
        }

        // Read back every written property and compare byte-for-byte (with known equivalences).
        let after: CameraSlotSnapshot
        do {
            after = try await readSlotLocked(slot, camera: camera)
        } catch {
            throw CameraError.outcomeUnknown(slot, "Write finished but read-back failed.")
        }
        let readMap = Dictionary(uniqueKeysWithValues: after.rawValues.map { ($0.code, $0.bytes) })
        let mismatches = plan.compactMap { item -> PropertyMismatch? in
            let actual = readMap[item.property.rawValue]
            return Self.equivalent(item.property, expected: item.bytes, actual: actual)
                ? nil : PropertyMismatch(property: item.property, expected: item.bytes, actual: actual)
        }
        return SlotWriteReport(slot: slot, after: after, mismatches: mismatches)
    }

    /// Known read-back equivalences reported by third parties.
    static func equivalent(_ p: FujiPresetProperty, expected: Data, actual: Data?) -> Bool {
        guard let actual else { return false }
        if expected == actual { return true }
        if p == .grain, expected == FujiRecipeCodec.u16(1) {
            return actual == FujiRecipeCodec.u16(6) || actual == FujiRecipeCodec.u16(7)
        }
        return false
    }

    static func map(_ error: Error) -> Error {
        switch error {
        case let e as PTPError:
            if case .response(let code, _) = e, code == .deviceBusy { return CameraError.busy }
            return CameraError.ptp(e)
        default:
            return error
        }
    }

    func diagnosticsLog() async -> [String] {
        await session.log.map { $0.line }
    }

    func disconnect() async {
        if opensPTPSession { await session.close() }
        identity = nil
    }
}

extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
