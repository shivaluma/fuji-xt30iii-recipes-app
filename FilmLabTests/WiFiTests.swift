import Testing
import Foundation
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Wi‑Fi: packets and decisions")
struct WiFiProtocolTests {
    @Test("Init packet: 82 bytes, type 1, version 0x8F53E4F2, GUID, UTF‑16LE name (libfuji/ptp-ip bytes)")
    func initPacket() {
        let p = Array(FujiWiFi.initPacket(clientName: "fudge"))
        #expect(p.count == 0x52)
        #expect(Array(p[0..<28]) == [0x52, 0, 0, 0, 1, 0, 0, 0, 0xF2, 0xE4, 0x53, 0x8F,
                                     0xAD, 0xA5, 0x48, 0x5D, 0x87, 0xB2, 0x7F, 0x0B, 0xD3, 0xD5, 0xDE, 0xD0, 0, 0, 0, 0])
        #expect(Array(p[28..<40]) == [0x66, 0, 0x75, 0, 0x64, 0, 0x67, 0, 0x65, 0, 0, 0])
        #expect(p[40...].allSatisfy { $0 == 0 })
        // Long names are cut so the NUL terminator always fits.
        let long = Array(FujiWiFi.initPacket(clientName: String(repeating: "A", count: 40)))
        #expect(long.count == 0x52 && long[80] == 0 && long[81] == 0)
    }

    @Test("Init reply: ack carries the camera name; fail carries the reason")
    func initReply() throws {
        #expect(try FujiWiFi.parseInitReply(FujiWiFi.initAck(cameraName: "X-T30 III")) == .accepted(cameraName: "X-T30 III"))
        var fail = PTPWriter(); fail.u32(12); fail.u32(5); fail.u32(0x2019)
        #expect(try FujiWiFi.parseInitReply(fail.data) == .rejected(reason: 0x2019))
        #expect(throws: PTPError.self) { try FujiWiFi.parseInitReply(Data([0x40, 0, 0, 0, 2, 0, 0, 0])) }
    }

    @Test("Event list round-trips; property integers follow libfuji's -1 convention")
    func events() throws {
        let e = try FujiWiFi.parseEvents(FujiWiFi.encodeEvents([(0xDF00, 2), (0xD222, 431)]))
        #expect(e == [0xDF00: 2, 0xD222: 431])
        #expect(throws: PTPError.self) { try FujiWiFi.parseEvents(Data([2, 0, 0x00, 0xDF])) }
        #expect(FujiWiFi.integer(Data([0x0C, 0x00, 0x02, 0x00])) == 0x2000C)
        #expect(FujiWiFi.integer(Data([5, 0])) == 5)
        #expect(FujiWiFi.integer(Data([1, 2, 3])) == -1)
        #expect(FujiWiFi.integer(nil) == -1)
    }

    @Test("ClientState: 20 after a Bluetooth handoff, 5 with a remote version, else the camera's mode")
    func clientState() {
        #expect(FujiWiFi.clientState(mode: .bluetoothHandoff, cameraState: 2, remoteVersion: 0x20008) == 20)
        #expect(FujiWiFi.clientState(mode: .wireless, cameraState: 2, remoteVersion: 0x20008) == 5)
        #expect(FujiWiFi.clientState(mode: .wireless, cameraState: 1, remoteVersion: -1) == 1)
        #expect(FujiWiFi.clientState(mode: .wireless, cameraState: 3, remoteVersion: -1) == 3)
        #expect(FujiWiFi.clientState(mode: .wireless, cameraState: 6, remoteVersion: 0x20008) == nil)
        #expect(FujiWiFi.clientState(mode: .wireless, cameraState: 9, remoteVersion: -1) == nil)
        #expect(FujiWiFi.effectiveMode(.bluetoothHandoff, remoteVersion: 0x20006) == .wireless)
        #expect(FujiWiFi.effectiveMode(.bluetoothHandoff, remoteVersion: 0x20007) == .bluetoothHandoff)
    }

    @Test("ObjectInfo round-trips the fields the browser uses")
    func objectInfo() throws {
        let info = FujiObjectInfo(compressedSize: 12_345_678, thumbSize: 9000, imageWidth: 6240, imageHeight: 4160,
                                  fileName: "DSCF1234.RAF", captureDateString: "20261103T104107")
        let back = try FujiObjectInfo.decode(info.encoded())
        #expect(back == info)
        #expect(back.isRAW && !back.isMovie)
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: try #require(back.captureDate))
        #expect([c.year, c.month, c.day, c.hour, c.minute, c.second] == [2026, 11, 3, 10, 41, 7])
    }

    @Test("Transfer meter: rate over the window, fraction and time left")
    func meter() {
        var m = TransferMeter(totalBytes: 10_000_000)
        #expect(m.bytesPerSecond == nil)
        m.add(1_000_000, at: 0)
        m.add(1_000_000, at: 0.5)
        m.add(2_000_000, at: 1.0)
        #expect(m.fraction == 0.4)
        #expect(m.bytesPerSecond == 3_000_000)
        #expect(m.secondsLeft == 2)
    }

    @Test("Import ledger remembers files across launches")
    func ledger() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID()).json")
        var a = ImportLedger(file: file)
        let k = ImportLedger.key(camera: "X-T30 III", fileName: "DSCF0001.JPG", captureDate: "20261103T104107")
        a.insert(k)
        #expect(ImportLedger(file: file).contains(k))
    }
}

@Suite("Wi‑Fi: end to end over TCP with the emulated camera", .serialized)
struct WiFiSessionTests {
    static func roll(_ n: Int = 3, size: Int = 2_500_000) -> [SimulatedWiFiCamera.Photo] {
        (0..<n).map { i in
            let data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ i) })
            return SimulatedWiFiCamera.Photo(fileName: String(format: "DSCF%04d.JPG", i + 1), data: data,
                                             thumbnail: Data([0xFF, 0xD8, UInt8(i)]), captureDate: "2026110\(i + 1)T120000")
        }
    }

    static func connect(_ camera: SimulatedWiFiCamera, mode: FujiWiFi.Mode = .wireless) async throws -> FujiWiFiSession {
        let channel = try await FujiWiFiChannel.open(host: "127.0.0.1", port: camera.port, clientName: "FilmLab",
                                                     wifiOnly: false, budget: .seconds(10))
        return FujiWiFiSession(channel: channel, mode: mode)
    }

    @Test("Handshake waits for OK on the camera, then browses, thumbnails and downloads the original in 1 MiB chunks")
    func browseAndDownload() async throws {
        let roll = Self.roll()
        let camera = try await SimulatedWiFiCamera.start(photos: roll)
        defer { camera.stop() }
        let session = try await Self.connect(camera)
        let steps = StepRecorder()
        let info = try await session.start { steps.add($0) }
        #expect(info.cameraName == "X-T30 III")
        #expect(info.objectCount == 3)
        #expect(steps.all.contains(.waitingForApproval) && steps.all.last == .ready)

        // Browsing sizes are the camera's placeholder until D227 = 1 is set for the download.
        #expect(try await session.objectInfo(2).compressedSize == 100 * 1024)
        #expect(try await session.thumbnail(3) == Data([0xFF, 0xD8, 2]))
        #expect(camera.record.thumbsWithoutInfo == 0)        // ObjectInfo always precedes GetThumb

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let progress = StepRecorder()
        let got = try await session.download(2, to: url) { done, _ in progress.add(done) }
        #expect(got.fileName == "DSCF0002.JPG")
        #expect(try Data(contentsOf: url) == roll[1].data)
        #expect(progress.count == 3)                          // 2.5 MB → three 1 MiB chunks

        await session.close()
        try await Task.sleep(for: .milliseconds(100))
        let r = camera.record
        // ClientState 5 (remote version present), version announced, D227 toggled around the download.
        let sets = r.sets.map { ($0.0, Array($0.1)) }
        #expect(sets.contains { $0 == (FujiWiFi.Property.clientState, [5, 0]) })
        #expect(sets.contains { $0 == (FujiWiFi.Property.remoteVersion, [0x0C, 0, 2, 0]) })
        #expect(sets.filter { $0.0 == FujiWiFi.Property.noCompression }.map(\.1) == [[1, 0], [0, 0]])
        // Never touches anything but the Wi‑Fi session properties.
        let allowed: Set<UInt16> = [FujiWiFi.Property.clientState, FujiWiFi.Property.remoteVersion, FujiWiFi.Property.noCompression,
                                    FujiWiFi.Property.compression, FujiWiFi.Property.getObjectVersion, FujiWiFi.Property.autoSaveVersion,
                                    FujiWiFi.Property.xappDF28]
        #expect(r.sets.allSatisfy { allowed.contains($0.0) })
        #expect(r.operations.first == PTPOperation.openSession.rawValue)
        #expect(r.operations.last == PTPOperation.closeSession.rawValue)
        #expect(r.goodbyes == 1)
    }

    @Test("Older firmware: no remote version → echoes GetObjectVersion; busy handshake is retried once")
    func olderFirmware() async throws {
        var options = SimulatedWiFiCamera.Options()
        options.remoteVersion = nil
        options.rejectFirstHandshake = true
        options.approvalPolls = 0
        let camera = try await SimulatedWiFiCamera.start(photos: Self.roll(1, size: 10), options: options)
        defer { camera.stop() }
        let session = try await Self.connect(camera)
        let info = try await session.start { _ in }
        #expect(info.objectCount == 1)
        await session.close()
        let sets = camera.record.sets.map { ($0.0, Array($0.1)) }
        #expect(sets.contains { $0 == (FujiWiFi.Property.clientState, [2, 0]) })
        #expect(sets.contains { $0.0 == FujiWiFi.Property.getObjectVersion })
        #expect(!sets.contains { $0.0 == FujiWiFi.Property.remoteVersion })
    }

    @Test("Bluetooth handoff: ClientState 20 and the XApp setup sequence")
    func handoff() async throws {
        var options = SimulatedWiFiCamera.Options()
        options.approvalPolls = 0
        let camera = try await SimulatedWiFiCamera.start(photos: Self.roll(2, size: 10), options: options)
        defer { camera.stop() }
        let session = try await Self.connect(camera, mode: .bluetoothHandoff)
        let info = try await session.start { _ in }
        #expect(info.mode == .bluetoothHandoff)
        #expect(info.objectCount == 2)
        await session.close()
        let r = camera.record
        #expect(r.sets.contains { $0.0 == FujiWiFi.Property.clientState && Array($0.1) == [20, 0] })
        let ops = r.operations
        let xapp = [FujiWiFi.Operation.xapp9054, FujiWiFi.Operation.xapp9055, FujiWiFi.Operation.xapp9050, FujiWiFi.Operation.xapp9053]
        #expect(ops.filter(xapp.contains) == xapp)
    }

    @Test("Nothing listening → a clear 'unreachable' error within the budget")
    func unreachable() async {
        await #expect(throws: WiFiError.self) {
            _ = try await FujiWiFiChannel.open(host: "127.0.0.1", port: 9, clientName: "FilmLab", wifiOnly: false, budget: .seconds(1))
        }
    }
}

final class StepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Any] = []
    func add(_ x: Any) { lock.withLock { items.append(x) } }
    var count: Int { lock.withLock { items.count } }
    var all: [FujiWiFiSession.Step] { lock.withLock { items.compactMap { $0 as? FujiWiFiSession.Step } } }
}
