import Foundation

/// Fujifilm Wi‑Fi photo transfer: identifiers, the connection handshake and the datasets the
/// camera sends. Pure Foundation; every byte is unit-tested (`WiFiProtocolTests`).
///
/// ⚠️ PROVENANCE: REPORTED BY THIRD PARTIES, not documented by Fujifilm, NOT verified on our own
/// camera (docs/wireless.md, checks W1–W8):
///  - petabyt/libfuji @41484e8 `lib/fuji.c`, `lib/fujiptp.h`, `lib/bluetooth.c` (Fudge app)
///  - petabyt/camlib @f1c94c6 (USB-style PTP containers over TCP)
///  - malc0mn/ptp-ip @992d64b `ip/packets_fuji.go` (packet captures of the same handshake)
/// Fujifilm doesn't speak standard PTP/IP: after an 82‑byte init packet, ordinary USB PTP
/// containers (the ones `PTPContainer` already encodes) flow over one TCP socket.
enum FujiWiFi {
    static let cameraHost = "192.168.0.1"
    /// Command/data socket — the only one browsing and downloading need. (55741 events and
    /// 55742 live view are opened only for remote shooting.)
    static let commandPort: UInt16 = 55740

    /// libfuji `lib/fuji.h`: GetPartialObject chunk.
    static let chunkSize: UInt32 = 0x10_0000

    enum Operation {
        static let getObjectInfo: UInt16 = 0x1008
        static let getObject: UInt16 = 0x1009
        static let getThumb: UInt16 = 0x100A
        static let getPartialObject: UInt16 = 0x101B
        // XApp session setup (libfuji fuji.c L290‑339); meaning unpublished, sent exactly as libfuji does.
        static let xapp9050: UInt16 = 0x9050
        static let xapp9053: UInt16 = 0x9053
        static let xapp9054: UInt16 = 0x9054
        static let xapp9055: UInt16 = 0x9055
    }

    enum Property {
        /// Poll for changes: `u16 count, count × {u16 property, u32 value}`.
        static let events: UInt16 = 0xD212
        static let xappObjectCountHint: UInt16 = 0xD220
        static let objectCount: UInt16 = 0xD222
        /// XApp: 1 = resized "smartphone" copy (400–800 KB); restored to 2 afterwards.
        static let compression: UInt16 = 0xD226
        /// Wi‑Fi: 1 = ObjectInfo reports the real size (otherwise a fixed 100 KB).
        static let noCompression: UInt16 = 0xD227
        static let xappD22B: UInt16 = 0xD22B
        static let storageID: UInt16 = 0xD244
        static let importObjectCount: UInt16 = 0xD620
        static let importObjectHandles: UInt16 = 0xD621
        /// 0 = waiting for the user to press OK, 1 = multiple transfer, 2 = full access,
        /// 3 = PC AutoSave, 6 = remote shooting.
        static let cameraState: UInt16 = 0xDF00
        static let clientState: UInt16 = 0xDF01
        static let df21: UInt16 = 0xDF21
        static let getObjectVersion: UInt16 = 0xDF22
        static let autoSaveVersion: UInt16 = 0xDF23
        static let remoteVersion: UInt16 = 0xDF24
        static let remoteGetObjectVersion: UInt16 = 0xDF25
        static let xappDF28: UInt16 = 0xDF28
    }

    /// Value FilmLab announces as its remote version (libfuji's `0x2000C`).
    static let announcedRemoteVersion: UInt32 = 0x2000C

    // MARK: Init handshake

    /// 82 bytes: length, type 1, protocol version `0x8F53E4F2`, a fixed GUID, then the client
    /// name as NUL‑terminated UTF‑16LE in a 54‑byte field (libfuji fujiptp.h L423‑434).
    static func initPacket(clientName: String) -> Data {
        var w = PTPWriter()
        w.u32(0x52); w.u32(1); w.u32(0x8F53_E4F2)
        for g: UInt32 in [0x5D48_A5AD, 0x0B7F_B287, 0xD0DE_D5D3, 0] { w.u32(g) }
        var name = Data()
        for unit in clientName.utf16.prefix(26) { name.append(UInt8(unit & 0xFF)); name.append(UInt8(unit >> 8)) }
        name.append(Data(count: 54 - name.count))
        w.bytes(name)
        return w.data
    }

    enum InitReply: Equatable, Sendable {
        case accepted(cameraName: String?)
        /// 0x2019 = busy / already connected to another device; 0x201D = protocol version.
        case rejected(reason: UInt32?)
    }

    /// `u32 length, u32 type (2 = ack, 5 = fail), …`; an ack carries `u32 connection, 16‑byte
    /// GUID, UTF‑16LE camera name`.
    static func parseInitReply(_ data: Data) throws -> InitReply {
        var r = PTPReader(data)
        let length = try r.u32()
        guard length >= 8, Int(length) <= data.count else { throw PTPError.invalidLength(length) }
        let type = try r.u32()
        guard type == 2 else { return .rejected(reason: try? r.u32()) }
        guard r.remaining >= 20 else { return .accepted(cameraName: nil) }
        _ = try r.u32()
        _ = try r.bytes(16)
        var units: [UInt16] = []
        while r.remaining >= 2, let u = try? r.u16(), u != 0 { units.append(u) }
        let name = String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespaces)
        return .accepted(cameraName: name.isEmpty ? nil : name)
    }

    /// The camera side of an ack (emulator and tests).
    static func initAck(cameraName: String) -> Data {
        var body = PTPWriter()
        body.u32(2); body.u32(1); body.bytes(Data(count: 16))
        for u in cameraName.utf16 { body.u16(u) }
        body.u16(0)
        var w = PTPWriter()
        w.u32(UInt32(body.data.count + 4)); w.bytes(body.data)
        return w.data
    }

    /// Sent after CloseSession, before closing the socket (libfuji fuji.c L41‑56).
    static let goodbye = Data([0x08, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])

    // MARK: Datasets

    /// `0xD212`: what changed since the last poll.
    static func parseEvents(_ data: Data) throws -> [UInt16: UInt32] {
        var r = PTPReader(data)
        let count = Int(try r.u16())
        guard count <= 512 else { throw PTPError.payloadTooLarge(count) }
        var out: [UInt16: UInt32] = [:]
        for _ in 0..<count { let p = try r.u16(); out[p] = try r.u32() }
        return out
    }

    static func encodeEvents(_ events: [(UInt16, UInt32)]) -> Data {
        var w = PTPWriter()
        w.u16(UInt16(events.count))
        for (p, v) in events { w.u16(p); w.u32(v) }
        return w.data
    }

    /// A 1/2/4‑byte little-endian property value, else -1 (libfuji's convention for "absent").
    static func integer(_ data: Data?) -> Int64 {
        guard let data else { return -1 }
        let b = Array(data)
        switch b.count {
        case 1: return Int64(b[0])
        case 2: return Int64(UInt16(b[0]) | UInt16(b[1]) << 8)
        case 4: return Int64(UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)
        default: return -1
        }
    }

    // MARK: Decisions

    enum Mode: String, Sendable, Equatable {
        /// The user started WIRELESS COMMUNICATION on the camera and the phone joined its network.
        case wireless
        /// The phone woke the camera's Wi‑Fi over Bluetooth (what XApp does).
        case bluetoothHandoff
    }

    /// `DF01` ClientState (libfuji fuji.c L191‑227). Nil = a camera state FilmLab doesn't handle.
    static func clientState(mode: Mode, cameraState: Int64, remoteVersion: Int64) -> UInt16? {
        if mode == .bluetoothHandoff { return 20 }
        if cameraState == 6 { return nil }       // remote shooting — not a transfer mode
        if remoteVersion != -1 { return 5 }
        switch cameraState {
        case 1, 2, 3: return UInt16(cameraState)
        default: return nil
        }
    }

    /// Bluetooth‑handoff sessions need remote version ≥ 0x20007, else libfuji falls back.
    static func effectiveMode(_ mode: Mode, remoteVersion: Int64) -> Mode {
        mode == .bluetoothHandoff && remoteVersion < 0x20007 ? .wireless : mode
    }
}

/// The PTP ObjectInfo dataset (ISO 15740 §5.5.2) — what the camera says about one file.
struct FujiObjectInfo: Equatable, Sendable {
    var storageID: UInt32 = 0
    var format: UInt16 = 0x3801
    var compressedSize: UInt32
    var thumbFormat: UInt16 = 0x3808
    var thumbSize: UInt32 = 0
    var thumbWidth: UInt32 = 0
    var thumbHeight: UInt32 = 0
    var imageWidth: UInt32 = 0
    var imageHeight: UInt32 = 0
    var fileName: String
    /// PTP date string, `YYYYMMDDThhmmss`.
    var captureDateString: String = ""

    var captureDate: Date? { Self.parseDate(captureDateString) }
    var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }
    var isRAW: Bool { fileExtension == "raf" }
    var isMovie: Bool { ["mov", "mp4"].contains(fileExtension) }

    static func decode(_ data: Data) throws -> FujiObjectInfo {
        var r = PTPReader(data)
        var info = FujiObjectInfo(compressedSize: 0, fileName: "")
        info.storageID = try r.u32()
        info.format = try r.u16()
        _ = try r.u16()                       // protection status
        info.compressedSize = try r.u32()
        info.thumbFormat = try r.u16()
        info.thumbSize = try r.u32()
        info.thumbWidth = try r.u32()
        info.thumbHeight = try r.u32()
        info.imageWidth = try r.u32()
        info.imageHeight = try r.u32()
        _ = try r.u32()                       // bit depth
        _ = try r.u32()                       // parent
        _ = try r.u16()                       // association type
        _ = try r.u32()                       // association description
        _ = try r.u32()                       // sequence number
        info.fileName = try r.string()
        info.captureDateString = (try? r.string()) ?? ""
        return info
    }

    func encoded() throws -> Data {
        var w = PTPWriter()
        w.u32(storageID); w.u16(format); w.u16(0); w.u32(compressedSize)
        w.u16(thumbFormat); w.u32(thumbSize); w.u32(thumbWidth); w.u32(thumbHeight)
        w.u32(imageWidth); w.u32(imageHeight); w.u32(24); w.u32(0); w.u16(0); w.u32(0); w.u32(0)
        try w.string(fileName); try w.string(captureDateString); try w.string(captureDateString); try w.string("")
        return w.data
    }

    static func parseDate(_ s: String) -> Date? {
        let digits = s.prefix(15)
        guard digits.count == 15 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current                  // the camera clock is local time
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.date(from: String(digits))
    }
}
