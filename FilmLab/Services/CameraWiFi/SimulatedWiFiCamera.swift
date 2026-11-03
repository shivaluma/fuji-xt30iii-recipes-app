import Foundation
import Network
import ImageIO
import UniformTypeIdentifiers

/// A Fujifilm camera's Wi‑Fi side, emulated on 127.0.0.1 — a real TCP server speaking the same
/// handshake and containers as `FujiWiFiProtocol`, so demo mode and tests exercise the real
/// socket code end to end. It models only what libfuji describes; it is NOT evidence that real
/// hardware behaves this way. Everything shown through it is labelled "Demo".
final class SimulatedWiFiCamera: @unchecked Sendable {
    struct Photo: Sendable {
        var fileName: String
        var data: Data
        var thumbnail: Data
        var captureDate: String
        var width: UInt32 = 0
        var height: UInt32 = 0
    }

    struct Options: Sendable {
        var cameraName = "X-T30 III"
        /// Event polls answered with "waiting for OK" before the simulated user presses OK.
        var approvalPolls = 3
        /// Reported `DF24`; nil = property not supported (older firmware).
        var remoteVersion: UInt32? = 0x2_0008
        /// Reject the first handshake as busy (libfuji retries once).
        var rejectFirstHandshake = false
        /// Throttle to roughly this many bytes per second (nil = loopback speed).
        var bytesPerSecond: Int?
    }

    /// What the emulated camera saw (for tests).
    struct Record: Sendable {
        var sets: [(UInt16, Data)] = []
        var operations: [UInt16] = []
        var thumbsWithoutInfo = 0
        var goodbyes = 0
    }

    let photos: [Photo]
    let options: Options
    private let listener: NWListener
    private let lock = NSLock()
    private var _record = Record()
    private var handshakes = 0
    private(set) var port: UInt16 = 0

    var record: Record { lock.withLock { _record } }

    private init(photos: [Photo], options: Options) throws {
        self.photos = photos
        self.options = options
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    static func start(photos: [Photo], options: Options = Options()) async throws -> SimulatedWiFiCamera {
        let camera = try SimulatedWiFiCamera(photos: photos, options: options)
        try await camera.listen()
        return camera
    }

    func stop() { listener.cancel() }

    private func listen() async throws {
        let once = OnceFlag()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if once.claim() { self.port = listener.port?.rawValue ?? 0; c.resume() }
                case .failed(let e):
                    if once.claim() { c.resume(throwing: e) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.serve(connection) }
            }
            listener.start(queue: DispatchQueue(label: "app.filmlab.sim-wifi"))
        }
    }

    private func note(_ change: (inout Record) -> Void) { lock.withLock { change(&_record) } }

    // MARK: Connection

    private func serve(_ connection: NWConnection) async {
        guard let stream = try? await TCPStream.accepted(connection) else { return }
        defer { stream.close() }
        do {
            let head = try await stream.receive(exactly: 4)
            let length = Int(FujiWiFi.integer(head))
            guard (8...4096).contains(length) else { return }
            let packet = head + (try await stream.receive(exactly: length - 4))
            guard packet.count == 0x52, FujiWiFi.integer(packet.subdata(in: 4..<8)) == 1,
                  FujiWiFi.integer(packet.subdata(in: 8..<12)) == 0x8F53_E4F2 else { return }
            let reject = lock.withLock { handshakes += 1; return options.rejectFirstHandshake && handshakes == 1 }
            if reject {
                var w = PTPWriter(); w.u32(12); w.u32(5); w.u32(0x2019)
                try await stream.send(w.data)
                return
            }
            try await stream.send(FujiWiFi.initAck(cameraName: options.cameraName))
            var state = SessionState()
            while true {
                let header = try await stream.receive(exactly: 8)
                if header == FujiWiFi.goodbye { note { $0.goodbyes += 1 }; return }
                let length = Int(FujiWiFi.integer(header.prefix(4)))
                guard length >= PTPContainer.headerSize else { return }
                let command = try PTPContainer.decode(header + (try await stream.receive(exactly: length - 8)))
                var outData: Data?
                if command.code == PTPOperation.setDevicePropValue.rawValue {
                    outData = try await FujiWiFiChannel.readContainer(stream).payload
                }
                note { $0.operations.append(command.code) }
                let (data, code) = handle(command, outData: outData, state: &state)
                var reply = Data()
                if let data {
                    reply += try PTPContainer(type: .data, code: command.code, transactionID: command.transactionID, payload: data).encoded()
                }
                reply += try PTPContainer(type: .response, code: code.rawValue, transactionID: command.transactionID).encoded()
                if let rate = options.bytesPerSecond, reply.count > 4096 {
                    try await Task.sleep(for: .seconds(Double(reply.count) / Double(rate)))
                }
                try await stream.send(reply)
            }
        } catch {
            return
        }
    }

    private struct SessionState {
        var polls = 0
        var described: Set<UInt32> = []
        var realSizes = false
    }

    private func u32(_ v: UInt32) -> Data { FujiRecipeCodec.u32(v) }

    private func handle(_ c: PTPContainer, outData: Data?, state: inout SessionState) -> (Data?, PTPResponseCode) {
        let p = c.parameters
        func photo(_ h: UInt32?) -> Photo? {
            guard let h, h >= 1, Int(h) <= photos.count else { return nil }
            return photos[Int(h) - 1]
        }
        switch c.code {
        case PTPOperation.openSession.rawValue, PTPOperation.closeSession.rawValue,
             FujiWiFi.Operation.xapp9050, FujiWiFi.Operation.xapp9053, FujiWiFi.Operation.xapp9054, FujiWiFi.Operation.xapp9055:
            return (nil, .ok)
        case PTPOperation.getDevicePropValue.rawValue:
            switch UInt16(truncatingIfNeeded: p.first ?? 0) {
            case FujiWiFi.Property.events:
                state.polls += 1
                let approved = state.polls > options.approvalPolls
                return (FujiWiFi.encodeEvents([(FujiWiFi.Property.cameraState, approved ? 2 : 0),
                                               (FujiWiFi.Property.objectCount, UInt32(photos.count))]), .ok)
            case FujiWiFi.Property.remoteVersion:
                guard let v = options.remoteVersion else { return (nil, .devicePropNotSupported) }
                return (u32(v), .ok)
            case FujiWiFi.Property.getObjectVersion, FujiWiFi.Property.remoteGetObjectVersion, FujiWiFi.Property.df21,
                 FujiWiFi.Property.storageID, FujiWiFi.Property.xappDF28, FujiWiFi.Property.xappD22B:
                return (u32(1), .ok)
            case FujiWiFi.Property.importObjectCount:
                return (u32(UInt32(photos.count)), .ok)
            default:
                return (nil, .devicePropNotSupported)
            }
        case PTPOperation.setDevicePropValue.rawValue:
            let prop = UInt16(truncatingIfNeeded: p.first ?? 0)
            note { $0.sets.append((prop, outData ?? Data())) }
            if prop == FujiWiFi.Property.noCompression { state.realSizes = FujiWiFi.integer(outData) == 1 }
            return (nil, .ok)
        case FujiWiFi.Operation.getObjectInfo:
            guard let photo = photo(p.first) else { return (nil, PTPResponseCode(rawValue: 0x2009)) }
            state.described.insert(p[0])
            let info = FujiObjectInfo(compressedSize: state.realSizes ? UInt32(photo.data.count) : 100 * 1024,
                                      thumbSize: UInt32(photo.thumbnail.count), imageWidth: photo.width, imageHeight: photo.height,
                                      fileName: photo.fileName, captureDateString: photo.captureDate)
            return ((try? info.encoded()), .ok)
        case FujiWiFi.Operation.getThumb:
            guard let photo = photo(p.first) else { return (nil, PTPResponseCode(rawValue: 0x2009)) }
            if !state.described.contains(p[0]) { note { $0.thumbsWithoutInfo += 1 } }
            return (photo.thumbnail, .ok)
        case FujiWiFi.Operation.getPartialObject:
            guard p.count == 3, let photo = photo(p.first) else { return (nil, PTPResponseCode(rawValue: 0x2009)) }
            let start = min(Int(p[1]), photo.data.count)
            let end = min(start + Int(p[2]), photo.data.count)
            return (photo.data.subdata(in: start..<end), .ok)
        default:
            return (nil, .operationNotSupported)
        }
    }

    // MARK: Demo content

    /// A small roll: the Mt Fuji sample plus synthetic frames, newest last (as the camera numbers them).
    static func demoRoll(bundle: Bundle = .main) -> [Photo] {
        var sources: [Data] = []
        if let fuji = DemoImageFactory.samplePhotoData(bundle: bundle) { sources.append(fuji) }
        for scene in DemoImageFactory.scenes {
            if let d = DemoImageFactory.jpegData(for: scene, size: CGSize(width: 1200, height: 800)) { sources.append(d) }
        }
        let base = Date().addingTimeInterval(-3600)
        var roll: [Photo] = []
        for i in 0..<12 {
            let data = sources[i % max(sources.count, 1)]
            let date = base.addingTimeInterval(Double(i) * 240)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            let size = pixelSize(data)
            roll.append(Photo(fileName: String(format: "DSCF%04d.JPG", 1201 + i), data: data,
                              thumbnail: thumbnailJPEG(data) ?? data, captureDate: f.string(from: date),
                              width: size.0, height: size.1))
        }
        return roll
    }

    static func thumbnailJPEG(_ data: Data, maxPixel: Int = 320) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                                                      kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private static func pixelSize(_ data: Data) -> (UInt32, UInt32) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return (UInt32(props[kCGImagePropertyPixelWidth] as? Int ?? 0), UInt32(props[kCGImagePropertyPixelHeight] as? Int ?? 0))
    }
}
