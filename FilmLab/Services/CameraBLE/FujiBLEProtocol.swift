import Foundation

/// Fujifilm Bluetooth LE protocol: identifiers, packet encoders and the pairing/sync handshake.
/// Pure Foundation, so every byte FilmLab would send is unit-tested without a camera.
///
/// ⚠️ PROVENANCE: REPORTED BY THIRD PARTIES, not documented by Fujifilm, and NOT verified on our
/// own camera (docs/wireless.md):
///  - gkoh/furble `lib/furble/Fujifilm*.{h,cpp}` (ESP32 remote; secure pairing since the
///    July 2025 firmware, tested by its users on real bodies)
///  - petabyt/libfuji `lib/bluetooth.c` (derivative of furble; adds the time-sync reply)
/// FilmLab sends only what those projects send: the pairing acknowledgement, a client name,
/// subscriptions, the geotag interval, time/location replies when the camera asks, and shutter
/// commands the user taps. It never reads or writes settings, backups or recipes over Bluetooth.
enum FujiBLE {
    // MARK: Advertisement

    static let companyID: UInt16 = 0x04D8

    // MARK: Services & characteristics (uppercase, as CoreBluetooth prints them)

    /// Advertised by secure-pairing cameras while PAIRING REGISTRATION is open.
    static let securePairingAdvertService = "A9D2B304-E8D6-4902-8336-352B772D7597"
    /// Secure pairing service; also advertised (with the camera serial) when a paired phone may reconnect.
    static let securePairService = "123D8F06-62A1-4935-9322-833C531EE225"
    static let secureStatus = "F557D96B-8284-4667-8793-B971C1DECA2A"
    /// Legacy pairing service and its token characteristic.
    static let legacyPairService = "91F1DE68-DFF6-466E-8B65-FF13B0F16FB8"
    static let legacyToken = "ABA356EB-9633-4E60-B73F-F52516DBD671"
    /// Client name ("identify"), in either pairing service.
    static let identity = "85B9163E-62D1-49FF-A6F5-054B4630D4A1"
    /// Older bodies advertise these.
    static let legacyAdvertServices = ["AF854C2E-B214-458E-97E2-912C4ECF2CB8", "117C4142-EDD4-4C77-8696-DD18EEBB770A"]

    // Subscriptions
    static let confService = "4C0020FE-F3B6-40DE-ACC9-77D129067B14"
    static let indication1 = "A68E3F66-0FCC-4395-8D4C-AA980B5877FA"
    static let indication2 = "BD17BA04-B76B-4892-A545-B73BA1F74DAE"
    /// Camera → phone: `02 00` = configured; libfuji answers with the current time.
    static let timeRequest = "F9150137-5D40-4801-A8DC-F7FC5B01DA50"
    /// Camera → phone: `01 00` = send location now.
    static let geotagRequest = "AD06C7B7-F41A-46F4-A29A-712055319122"
    static let notification6 = "E6692C5C-B7CD-44F4-95FC-EDA07CE32560"
    static let notifyService = "4E941240-D01D-46B9-A5EA-67636806830B"
    static let notification4 = "BF6DC9CF-3606-4EC9-A4C8-D77576E93EA4"
    static let notification5 = "75823784-FBB7-4B71-ABAE-CD9A34072E3C"
    static let notification7 = "AAB609C4-94DD-4D89-BC60-665D5090B828"
    static let notification8 = "2A125640-706D-4DD1-B420-C0F4AB93C361"
    static let notification9 = "82A9F452-C5CE-4EF5-8203-3FC9A47F8171"
    static let notification10 = "DEEF7187-3F43-4364-9E22-11A8C8A15951"
    static let geotagInterval = "C95D91AE-B247-4D6D-8661-7DD5D6A0F85B"

    // Writes
    static let time = "B9BFD37F-CCAD-4D36-A1EE-018E792B3EDF"
    static let geotag = "0F36EC14-29E5-411A-A1B6-64EE8383F090"
    static let shutter = "7FCF49C6-4FF0-4777-A03D-1A79166AF7A8"

    // Wi‑Fi handoff (libfuji lib/bluetooth.c L310‑388): read the SSID, write `04 00` to start the
    // camera's access point, read the password, then wait for `indication1` (byte 0: 1 = ready).
    /// In `notifyService`; same UUID as `notification4`.
    static let wifiSSID = "BF6DC9CF-3606-4EC9-A4C8-D77576E93EA4"
    static let wifiPassword = "E809256A-915C-4967-92E8-53B7D4CAD213"
    static let wifiService = "6514EB81-4E8F-458D-AA2A-E691336CDFAC"
    static let wifiStart = "600655E6-3637-42F1-8FB2-44EFC5C63B13"
    static let wifiStartValue = Data([0x04, 0x00])

    enum WiFiReadiness: Equatable, Sendable {
        case ready, busy, timedOut, unknown(UInt8?)
        init(indication: Data) {
            switch indication.first {
            case 1: self = .ready
            case 0: self = .busy
            case 0xFF: self = .timedOut
            case let b: self = .unknown(b)
            }
        }
    }

    /// SSID/password characteristics hold NUL-padded UTF‑8.
    static func text(_ data: Data) -> String? {
        let s = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // Device Information (standard)
    static let firmwareRevision = "2A26"

    /// Services to look for when asking iOS which cameras another app already connected.
    static var knownServices: [String] { legacyAdvertServices + [securePairingAdvertService, securePairService] }

    // MARK: Packets

    /// `u16 year, u8 month, day, hour, minute, second` (little-endian), in the phone's local time.
    static func timePacket(_ date: Date, calendar: Calendar = .current) -> Data {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var d = Data()
        d.append(le16(UInt16(c.year ?? 2000)))
        for v in [c.month, c.day, c.hour, c.minute, c.second] { d.append(UInt8(clamping: v ?? 0)) }
        return d
    }

    /// `i32 lat×1e7, i32 lon×1e7, i32 altitude (m), 4 pad, time` (little-endian), as furble sends.
    static func geotagPacket(latitude: Double, longitude: Double, altitude: Double, date: Date, calendar: Calendar = .current) -> Data {
        var d = Data()
        d.append(le32(Int32(clamping: Int64((latitude * 10_000_000).rounded()))))
        d.append(le32(Int32(clamping: Int64((longitude * 10_000_000).rounded()))))
        d.append(le32(Int32(clamping: Int64(altitude.rounded()))))
        d.append(Data(count: 4))
        d.append(timePacket(date, calendar: calendar))
        return d
    }

    /// Secure pairing: echo the 4-byte status with byte 3 set to 0x20.
    static func secureAck(status: Data) -> Data? {
        guard status.count == 4 else { return nil }
        var ack = Data(status)
        ack[ack.startIndex + 3] = 0x20
        return ack
    }

    enum Shutter {
        static let command = Data([0x01, 0x00])
        static let press = Data([0x02, 0x00])
        static let focus = Data([0x03, 0x00])
        static let release = Data([0x00, 0x00])
    }

    static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8)]) }
    static func le32(_ v: Int32) -> Data {
        let u = UInt32(bitPattern: v)
        return Data([UInt8(u & 0xff), UInt8((u >> 8) & 0xff), UInt8((u >> 16) & 0xff), UInt8(u >> 24)])
    }
}

/// What a Fujifilm camera's advertisement tells us. Pure, unit-tested.
struct FujiBLEAdvertisement: Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        /// Secure firmware with PAIRING REGISTRATION open.
        case pairing
        /// Secure firmware looking for a phone it already knows.
        case paired
        /// Older protocol (token pairing).
        case legacy
        /// Fujifilm company ID only.
        case unknown

        var label: String {
            switch self {
            case .pairing: "Ready to pair"
            case .paired: "Paired, nearby"
            case .legacy, .unknown: "Nearby"
            }
        }
    }

    var name: String?
    var phase: Phase
    var model: CameraModelInfo?
    /// Legacy pairing token (4 bytes) from the manufacturer data.
    var token: Data?

    static let companyID = FujiBLE.companyID

    /// Returns nil unless the advertisement is from a Fujifilm camera.
    static func parse(localName: String?, manufacturerData: Data?, serviceUUIDs: [String]) -> FujiBLEAdvertisement? {
        let services = Set(serviceUUIDs.map { $0.uppercased() })
        let m = manufacturerData.map { Array($0) } ?? []
        let isFujiCompany = m.count >= 2 && (UInt16(m[0]) | UInt16(m[1]) << 8) == companyID
        let phase: Phase
        if services.contains(FujiBLE.securePairingAdvertService) { phase = .pairing }
        else if services.contains(FujiBLE.securePairService) { phase = .paired }
        else if !services.isDisjoint(with: FujiBLE.legacyAdvertServices) { phase = .legacy }
        else if isFujiCompany { phase = .unknown }
        else { return nil }
        // furble/libfuji: company ID, type 0x02, 4-byte token.
        let token = isFujiCompany && m.count == 7 && m[2] == 0x02 ? Data(m[3..<7]) : nil
        return FujiBLEAdvertisement(name: localName, phase: phase, model: localName.flatMap(CameraCatalog.recognize), token: token)
    }
}

/// Pairing and session handshake as a pure state machine: feed it what the camera exposes and
/// says, and it returns the next reads/writes. The CoreBluetooth layer only executes them.
struct FujiBLEHandshake: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case read(String)
        case write(String, Data)
        case subscribe(String)
        /// Handshake done: the camera accepted this phone.
        case ready
        case fail(String)
    }

    enum Phase: Equatable, Sendable { case idle, awaitingStatus, ready, failed }

    var clientName: String
    var geotagIntervalSeconds: UInt16 = 10
    private(set) var phase: Phase = .idle
    private var available: Set<String> = []

    init(clientName: String) { self.clientName = clientName }

    /// After service/characteristic discovery.
    mutating func start(characteristics: Set<String>, legacyToken: Data?) -> [Action] {
        available = Set(characteristics.map { $0.uppercased() })
        if available.contains(FujiBLE.secureStatus) {
            // Reading the encrypted status starts iOS pairing (code shown on phone and camera).
            phase = .awaitingStatus
            return [.read(FujiBLE.secureStatus)]
        }
        if available.contains(FujiBLE.legacyToken) {
            guard let legacyToken, legacyToken.count == 4 else {
                phase = .failed
                return [.fail("Open PAIRING REGISTRATION on the camera, then try again.")]
            }
            return [.write(FujiBLE.legacyToken, legacyToken)] + session()
        }
        phase = .failed
        return [.fail("This camera doesn't expose a pairing service FilmLab knows.")]
    }

    mutating func didRead(_ characteristic: String, value: Data) -> [Action] {
        guard phase == .awaitingStatus, characteristic.uppercased() == FujiBLE.secureStatus else { return [] }
        guard let ack = FujiBLE.secureAck(status: value) else {
            phase = .failed
            return [.fail("The camera answered pairing unexpectedly (\(value.count) bytes).")]
        }
        return [.write(FujiBLE.secureStatus, ack)] + session()
    }

    /// Camera → phone notification. `location` is nil when location sharing is off/unavailable.
    func didNotify(_ characteristic: String, value: Data, now: Date,
                   location: (latitude: Double, longitude: Double, altitude: Double)?) -> [Action] {
        guard phase == .ready else { return [] }
        let bytes = Array(value)
        switch characteristic.uppercased() {
        case FujiBLE.timeRequest where bytes.starts(with: [0x02, 0x00]) && available.contains(FujiBLE.time):
            return [.write(FujiBLE.time, FujiBLE.timePacket(now))]
        case FujiBLE.geotagRequest where bytes.starts(with: [0x01, 0x00]) && available.contains(FujiBLE.geotag):
            guard let location else { return [] }
            return [.write(FujiBLE.geotag, FujiBLE.geotagPacket(latitude: location.latitude, longitude: location.longitude,
                                                                  altitude: location.altitude, date: now))]
        default:
            return []
        }
    }

    /// Identify, subscribe (only to what exists), set the geotag interval.
    private mutating func session() -> [Action] {
        phase = .ready
        var actions: [Action] = []
        if available.contains(FujiBLE.identity) { actions.append(.write(FujiBLE.identity, Data(clientName.utf8))) }
        let subscriptions = [FujiBLE.indication1, FujiBLE.indication2, FujiBLE.timeRequest, FujiBLE.geotagRequest,
                             FujiBLE.notification4, FujiBLE.notification5, FujiBLE.notification6, FujiBLE.notification7,
                             FujiBLE.notification8, FujiBLE.notification9, FujiBLE.notification10, FujiBLE.geotagInterval]
        actions += subscriptions.filter(available.contains).map(Action.subscribe)
        if available.contains(FujiBLE.geotagInterval) {
            actions.append(.write(FujiBLE.geotagInterval, FujiBLE.le16(geotagIntervalSeconds)))
        }
        if available.contains(FujiBLE.firmwareRevision) { actions.append(.read(FujiBLE.firmwareRevision)) }
        actions.append(.ready)
        return actions
    }

    /// Remote shutter: full press, then release.
    static let takePhoto: [[Action]] = [
        [.write(FujiBLE.shutter, FujiBLE.Shutter.command), .write(FujiBLE.shutter, FujiBLE.Shutter.press)],
        [.write(FujiBLE.shutter, FujiBLE.Shutter.command), .write(FujiBLE.shutter, FujiBLE.Shutter.release)],
    ]
}
