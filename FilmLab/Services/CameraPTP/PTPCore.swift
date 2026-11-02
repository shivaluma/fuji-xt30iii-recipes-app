import Foundation

// Generic ISO 15740 (PTP) primitives. Only STANDARD operation/response codes are declared here.
// Fujifilm-specific codes live in FujiPTPPropertyTable with per-code provenance.

enum PTPContainerType: UInt16, Sendable {
    case command = 1, data = 2, response = 3, event = 4
}

enum PTPOperation: UInt16, Sendable {
    case getDeviceInfo = 0x1001
    case openSession = 0x1002
    case closeSession = 0x1003
    case getDevicePropDesc = 0x1014
    case getDevicePropValue = 0x1015
    case setDevicePropValue = 0x1016
}

struct PTPResponseCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    var rawValue: UInt16
    init(rawValue: UInt16) { self.rawValue = rawValue }

    static let ok = PTPResponseCode(rawValue: 0x2001)
    static let generalError = PTPResponseCode(rawValue: 0x2002)
    static let sessionNotOpen = PTPResponseCode(rawValue: 0x2003)
    static let operationNotSupported = PTPResponseCode(rawValue: 0x2005)
    static let deviceBusy = PTPResponseCode(rawValue: 0x2019)
    static let invalidDevicePropFormat = PTPResponseCode(rawValue: 0x201B)
    static let invalidDevicePropValue = PTPResponseCode(rawValue: 0x201C)
    static let sessionAlreadyOpen = PTPResponseCode(rawValue: 0x201E)
    static let devicePropNotSupported = PTPResponseCode(rawValue: 0x200A)

    var description: String {
        let name: String
        switch self {
        case .ok: name = "OK"
        case .generalError: name = "GeneralError"
        case .sessionNotOpen: name = "SessionNotOpen"
        case .operationNotSupported: name = "OperationNotSupported"
        case .deviceBusy: name = "DeviceBusy"
        case .invalidDevicePropFormat: name = "InvalidDevicePropFormat"
        case .invalidDevicePropValue: name = "InvalidDevicePropValue"
        case .sessionAlreadyOpen: name = "SessionAlreadyOpen"
        case .devicePropNotSupported: name = "DevicePropNotSupported"
        default: name = "Unknown"
        }
        return String(format: "0x%04X (%@)", rawValue, name)
    }
}

enum PTPError: Error, Equatable, Sendable, LocalizedError {
    case truncated(needed: Int, available: Int)
    case invalidLength(UInt32)
    case invalidContainerType(UInt16)
    case unexpectedContainerType(expected: PTPContainerType, got: UInt16)
    case transactionMismatch(expected: UInt32, got: UInt32)
    case payloadTooLarge(Int)
    case tooManyParameters(Int)
    case invalidString
    case response(PTPResponseCode, operation: UInt16)
    case timeout(operation: UInt16)
    case cancelled
    case disconnected
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .truncated(let n, let a): "PTP packet truncated (needed \(n) bytes, had \(a))."
        case .invalidLength(let l): "PTP container has invalid length \(l)."
        case .invalidContainerType(let t): "PTP container has invalid type \(t)."
        case .unexpectedContainerType(let e, let g): "Expected PTP \(e) container, got type \(g)."
        case .transactionMismatch(let e, let g): "PTP transaction ID mismatch (expected \(e), got \(g))."
        case .payloadTooLarge(let n): "PTP payload of \(n) bytes exceeds the safety limit."
        case .tooManyParameters(let n): "PTP container has \(n) parameters (max 5)."
        case .invalidString: "Malformed PTP string."
        case .response(let code, let op): String(format: "Camera answered %@ to operation 0x%04X.", code.description, op)
        case .timeout(let op): String(format: "Camera did not answer operation 0x%04X in time.", op)
        case .cancelled: "Operation cancelled."
        case .disconnected: "Camera disconnected."
        case .transport(let m): m
        }
    }
}

// MARK: - Little-endian reader/writer

struct PTPReader {
    let data: Data
    private(set) var offset: Int

    init(_ data: Data, offset: Int = 0) {
        // Re-base so indices start at 0 even for Data slices.
        self.data = Data(data)
        self.offset = offset
    }

    var remaining: Int { data.count - offset }

    private mutating func take(_ n: Int) throws -> Data {
        guard n >= 0, remaining >= n else { throw PTPError.truncated(needed: n, available: max(remaining, 0)) }
        defer { offset += n }
        return data.subdata(in: offset..<(offset + n))
    }

    mutating func u8() throws -> UInt8 { try take(1)[0] }

    mutating func u16() throws -> UInt16 {
        let b = try take(2)
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    mutating func u32() throws -> UInt32 {
        let b = try take(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    mutating func bytes(_ n: Int) throws -> Data { try take(n) }

    /// PTP string: u8 character count (incl. terminating NUL), then UTF-16LE code units.
    mutating func string() throws -> String {
        let count = Int(try u8())
        if count == 0 { return "" }
        var units: [UInt16] = []
        units.reserveCapacity(count)
        for _ in 0..<count { units.append(try u16()) }
        guard units.last == 0 else { throw PTPError.invalidString }
        units.removeLast()
        return String(decoding: units, as: UTF16.self)
    }

    /// PTP array of u16: u32 count then elements. Bounded to avoid absurd allocations.
    mutating func u16Array(limit: Int = 4096) throws -> [UInt16] {
        let n = Int(try u32())
        guard n <= limit else { throw PTPError.payloadTooLarge(n) }
        return try (0..<n).map { _ in try u16() }
    }
}

struct PTPWriter {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8)) }
    mutating func u32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { data.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func bytes(_ d: Data) { data.append(d) }

    /// Encodes a PTP string. Throws if longer than the 255-unit PTP limit.
    mutating func string(_ s: String) throws {
        if s.isEmpty { u8(0); return }
        let units = Array(s.utf16) + [0]
        guard units.count <= 255 else { throw PTPError.invalidString }
        u8(UInt8(units.count))
        units.forEach { u16($0) }
    }
}

// MARK: - Containers

struct PTPContainer: Equatable, Sendable {
    static let headerSize = 12
    /// Safety bound for anything we parse from the wire (RAF files go through a separate path).
    static let maxPayload = 64 * 1024 * 1024

    var type: PTPContainerType
    var code: UInt16
    var transactionID: UInt32
    /// For command/response containers: up to 5 u32 parameters.
    var parameters: [UInt32] = []
    /// For data containers.
    var payload: Data = Data()

    func encoded() throws -> Data {
        guard parameters.count <= 5 else { throw PTPError.tooManyParameters(parameters.count) }
        let body = type == .data ? payload.count : parameters.count * 4
        guard body <= Self.maxPayload else { throw PTPError.payloadTooLarge(body) }
        var w = PTPWriter()
        w.u32(UInt32(Self.headerSize + body))
        w.u16(type.rawValue)
        w.u16(code)
        w.u32(transactionID)
        if type == .data { w.bytes(payload) } else { parameters.forEach { w.u32($0) } }
        return w.data
    }

    /// Strict decoder: validates declared length against available bytes, type, and parameter count.
    static func decode(_ raw: Data) throws -> PTPContainer {
        var r = PTPReader(raw)
        let length = try r.u32()
        guard length >= UInt32(headerSize) else { throw PTPError.invalidLength(length) }
        guard Int(length) - headerSize <= maxPayload else { throw PTPError.payloadTooLarge(Int(length)) }
        guard Int(length) <= raw.count else { throw PTPError.truncated(needed: Int(length), available: raw.count) }
        let typeRaw = try r.u16()
        guard let type = PTPContainerType(rawValue: typeRaw) else { throw PTPError.invalidContainerType(typeRaw) }
        let code = try r.u16()
        let tid = try r.u32()
        let bodyCount = Int(length) - headerSize
        var c = PTPContainer(type: type, code: code, transactionID: tid)
        if type == .data {
            c.payload = try r.bytes(bodyCount)
        } else {
            guard bodyCount % 4 == 0 else { throw PTPError.invalidLength(length) }
            guard bodyCount / 4 <= 5 else { throw PTPError.tooManyParameters(bodyCount / 4) }
            c.parameters = try (0..<(bodyCount / 4)).map { _ in try r.u32() }
        }
        return c
    }

    static func command(_ code: UInt16, transactionID: UInt32, parameters: [UInt32] = []) -> PTPContainer {
        PTPContainer(type: .command, code: code, transactionID: transactionID, parameters: parameters)
    }
}

/// Result of a single PTP transaction as seen by the session layer.
struct PTPTransactionResult: Sendable {
    var response: PTPContainer
    /// Data-in phase payload (no container header).
    var inData: Data

    var responseCode: PTPResponseCode { PTPResponseCode(rawValue: response.code) }
}

// MARK: - DeviceInfo (standard dataset)

struct PTPDeviceInfo: Equatable, Sendable {
    var standardVersion: UInt16
    var vendorExtensionID: UInt32
    var vendorExtensionVersion: UInt16
    var vendorExtensionDesc: String
    var functionalMode: UInt16
    var operationsSupported: [UInt16]
    var eventsSupported: [UInt16]
    var devicePropertiesSupported: [UInt16]
    var captureFormats: [UInt16]
    var imageFormats: [UInt16]
    var manufacturer: String
    var model: String
    var deviceVersion: String
    var serialNumber: String

    static func decode(_ data: Data) throws -> PTPDeviceInfo {
        var r = PTPReader(data)
        return PTPDeviceInfo(
            standardVersion: try r.u16(),
            vendorExtensionID: try r.u32(),
            vendorExtensionVersion: try r.u16(),
            vendorExtensionDesc: try r.string(),
            functionalMode: try r.u16(),
            operationsSupported: try r.u16Array(),
            eventsSupported: try r.u16Array(),
            devicePropertiesSupported: try r.u16Array(),
            captureFormats: try r.u16Array(),
            imageFormats: try r.u16Array(),
            manufacturer: try r.string(),
            model: try r.string(),
            deviceVersion: try r.string(),
            serialNumber: try r.string()
        )
    }

    func encoded() throws -> Data {
        var w = PTPWriter()
        w.u16(standardVersion); w.u32(vendorExtensionID); w.u16(vendorExtensionVersion)
        try w.string(vendorExtensionDesc); w.u16(functionalMode)
        for arr in [operationsSupported, eventsSupported, devicePropertiesSupported, captureFormats, imageFormats] {
            w.u32(UInt32(arr.count)); arr.forEach { w.u16($0) }
        }
        try w.string(manufacturer); try w.string(model); try w.string(deviceVersion); try w.string(serialNumber)
        return w.data
    }
}
