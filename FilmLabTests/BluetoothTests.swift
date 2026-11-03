import Testing
import Foundation
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Bluetooth: advertisements")
struct BluetoothAdvertisementTests {
    @Test("Secure pairing, reconnect and legacy services set the phase; the name gives the model")
    func phases() throws {
        let pairing = try #require(FujiBLEAdvertisement.parse(localName: "X-T30 III_1A2B", manufacturerData: nil,
                                                               serviceUUIDs: ["a9d2b304-e8d6-4902-8336-352b772d7597"]))
        #expect(pairing.phase == .pairing)
        #expect(pairing.model?.id == "x-t30-iii")

        let paired = try #require(FujiBLEAdvertisement.parse(localName: "X100VI", manufacturerData: nil,
                                                             serviceUUIDs: [FujiBLE.securePairService]))
        #expect(paired.phase == .paired)
        #expect(paired.model?.id == "x100vi")      // never mistaken for the X100V

        let legacy = try #require(FujiBLEAdvertisement.parse(localName: "X-T4_0001", manufacturerData: nil,
                                                             serviceUUIDs: ["AF854C2E-B214-458E-97E2-912C4ECF2CB8"]))
        #expect(legacy.phase == .legacy)
        #expect(legacy.model?.id == "x-t4")
    }

    @Test("Company ID and legacy token come from the manufacturer data; other devices are ignored")
    func manufacturerData() throws {
        let tokenAd = try #require(FujiBLEAdvertisement.parse(localName: nil, manufacturerData: Data([0xD8, 0x04, 0x02, 0xDE, 0xAD, 0xBE, 0xEF]), serviceUUIDs: []))
        #expect(tokenAd.phase == .unknown)
        #expect(tokenAd.token == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        // Secure serial advertisement (5 bytes) is not a token.
        let secure = try #require(FujiBLEAdvertisement.parse(localName: nil, manufacturerData: Data([0xD8, 0x04, 0x02, 1, 2, 3, 4, 5]),
                                                             serviceUUIDs: [FujiBLE.securePairService]))
        #expect(secure.token == nil)
        #expect(FujiBLEAdvertisement.parse(localName: "X-T30 III", manufacturerData: Data([0x4C, 0x00]), serviceUUIDs: []) == nil)
        #expect(FujiBLEAdvertisement.parse(localName: "Headphones", manufacturerData: nil, serviceUUIDs: ["180D"]) == nil)
        #expect(FujiBLEAdvertisement.parse(localName: nil, manufacturerData: Data([0xD8]), serviceUUIDs: []) == nil)
    }
}

@Suite("Bluetooth: packets and handshake")
struct BluetoothProtocolTests {
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    // 2026-11-03 10:41:07 UTC
    static let date = Date(timeIntervalSince1970: 1_793_702_467)

    @Test("Time packet: u16 LE year, then month, day, hour, minute, second")
    func time() {
        #expect(Array(FujiBLE.timePacket(Self.date, calendar: Self.utc)) == [0xEA, 0x07, 11, 3, 10, 41, 7])
    }

    @Test("Geotag packet: lat/lon ×1e7, altitude in metres, 4 pad bytes, time — 23 bytes, little-endian")
    func geotag() {
        let d = Array(FujiBLE.geotagPacket(latitude: 35.3606, longitude: 138.7274, altitude: 3776, date: Self.date, calendar: Self.utc))
        #expect(d.count == 23)
        func i32(_ o: Int) -> Int32 { Int32(bitPattern: UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24) }
        #expect(i32(0) == 353_606_000)
        #expect(i32(4) == 1_387_274_000)
        #expect(i32(8) == 3776)
        #expect(Array(d[12..<16]) == [0, 0, 0, 0])
        #expect(Array(d[16...]) == [0xEA, 0x07, 11, 3, 10, 41, 7])
        // Southern/western hemispheres stay signed.
        let s = Array(FujiBLE.geotagPacket(latitude: -33.8568, longitude: -70.6483, altitude: 0, date: Self.date, calendar: Self.utc))
        #expect(Int32(bitPattern: UInt32(s[0]) | UInt32(s[1]) << 8 | UInt32(s[2]) << 16 | UInt32(s[3]) << 24) == -338_568_000)
    }

    @Test("Secure pairing ack echoes the status with byte 3 = 0x20")
    func ack() {
        #expect(FujiBLE.secureAck(status: Data([0x01, 0x02, 0x03, 0x04])) == Data([0x01, 0x02, 0x03, 0x20]))
        #expect(FujiBLE.secureAck(status: Data([0x01, 0x02])) == nil)
    }

    @Test("Secure handshake: read status → ack, identify, subscribe to what exists, geotag interval, ready")
    func secure() {
        var h = FujiBLEHandshake(clientName: "FilmLab")
        let chars: Set<String> = [FujiBLE.secureStatus, FujiBLE.identity, FujiBLE.indication1, FujiBLE.timeRequest,
                                  FujiBLE.geotagRequest, FujiBLE.geotagInterval, FujiBLE.time, FujiBLE.geotag, FujiBLE.shutter]
        #expect(h.start(characteristics: chars, legacyToken: nil) == [.read(FujiBLE.secureStatus)])
        #expect(h.phase == .awaitingStatus)
        // Nothing is answered before pairing completes.
        #expect(h.didNotify(FujiBLE.timeRequest, value: Data([2, 0]), now: Self.date, location: nil).isEmpty)

        let actions = h.didRead(FujiBLE.secureStatus, value: Data([9, 8, 7, 6]))
        #expect(actions == [
            .write(FujiBLE.secureStatus, Data([9, 8, 7, 0x20])),
            .write(FujiBLE.identity, Data("FilmLab".utf8)),
            .subscribe(FujiBLE.indication1), .subscribe(FujiBLE.timeRequest), .subscribe(FujiBLE.geotagRequest),
            .subscribe(FujiBLE.geotagInterval),
            .write(FujiBLE.geotagInterval, Data([10, 0])),
            .ready,
        ])
        #expect(h.phase == .ready)
        // Never writes settings, backups or recipes.
        for case .write(let uuid, _) in actions {
            #expect([FujiBLE.secureStatus, FujiBLE.identity, FujiBLE.geotagInterval].contains(uuid))
        }
    }

    @Test("Legacy handshake needs the advertised token; without it, it fails clearly")
    func legacy() {
        var h = FujiBLEHandshake(clientName: "FilmLab")
        let chars: Set<String> = [FujiBLE.legacyToken, FujiBLE.identity]
        let token = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(h.start(characteristics: chars, legacyToken: token) == [
            .write(FujiBLE.legacyToken, token), .write(FujiBLE.identity, Data("FilmLab".utf8)), .ready,
        ])
        var noToken = FujiBLEHandshake(clientName: "FilmLab")
        if case .fail = noToken.start(characteristics: chars, legacyToken: nil).first {} else { Issue.record("expected failure") }
        var unknown = FujiBLEHandshake(clientName: "FilmLab")
        if case .fail = unknown.start(characteristics: ["1234"], legacyToken: nil).first {} else { Issue.record("expected failure") }
    }

    @Test("Camera requests: time on 02 00, location on 01 00 only when sharing")
    func requests() {
        var h = FujiBLEHandshake(clientName: "FilmLab")
        _ = h.start(characteristics: [FujiBLE.legacyToken, FujiBLE.time, FujiBLE.geotag], legacyToken: Data([1, 2, 3, 4]))
        #expect(h.didNotify(FujiBLE.timeRequest, value: Data([2, 0]), now: Self.date, location: nil)
                == [.write(FujiBLE.time, FujiBLE.timePacket(Self.date))])
        #expect(h.didNotify(FujiBLE.timeRequest, value: Data([1, 0]), now: Self.date, location: nil).isEmpty)
        #expect(h.didNotify(FujiBLE.geotagRequest, value: Data([1, 0]), now: Self.date, location: nil).isEmpty)
        let fuji = (latitude: 35.3606, longitude: 138.7274, altitude: 3776.0)
        #expect(h.didNotify(FujiBLE.geotagRequest, value: Data([1, 0]), now: Self.date, location: fuji)
                == [.write(FujiBLE.geotag, FujiBLE.geotagPacket(latitude: fuji.latitude, longitude: fuji.longitude, altitude: fuji.altitude, date: Self.date))])
    }

    @Test("Remote shutter: command + press, then command + release")
    func shutter() {
        #expect(FujiBLEHandshake.takePhoto == [
            [.write(FujiBLE.shutter, Data([1, 0])), .write(FujiBLE.shutter, Data([2, 0]))],
            [.write(FujiBLE.shutter, Data([1, 0])), .write(FujiBLE.shutter, Data([0, 0]))],
        ])
    }
}
