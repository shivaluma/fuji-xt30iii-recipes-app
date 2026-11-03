import Foundation

/// PTP over the camera's Wi‑Fi: USB-style containers on one TCP socket (camlib `PTP_IP_USB`).
/// Plugs into the same `PTPSession` the USB path uses.
final class FujiWiFiChannel: PTPCommandChannel {
    let stream: TCPStream
    let cameraName: String?
    var echoesTransactionIDs: Bool { true }

    private init(stream: TCPStream, cameraName: String?) {
        self.stream = stream
        self.cameraName = cameraName
    }

    /// Connects and runs the init handshake, retrying while the camera's network comes up (a
    /// camera woken over Bluetooth needs a few seconds). Gives up after `budget`.
    static func open(host: String = FujiWiFi.cameraHost, port: UInt16 = FujiWiFi.commandPort,
                     clientName: String, wifiOnly: Bool, budget: Duration = .seconds(30)) async throws -> FujiWiFiChannel {
        let clock = ContinuousClock()
        let deadline = clock.now + budget
        var lastError: Error = PTPError.disconnected
        var rejectedOnce = false
        while clock.now < deadline {
            try Task.checkCancellation()
            do {
                let stream = try await TCPStream.connect(host: host, port: port, wifiOnly: wifiOnly, timeout: .seconds(3))
                do {
                    try await stream.send(FujiWiFi.initPacket(clientName: clientName))
                    let head = try await withPTPTimeout(.seconds(10), operation: 0) { try await stream.receive(exactly: 4) }
                    let length = Int(FujiWiFi.integer(head))
                    guard (8...4096).contains(length) else { throw PTPError.invalidLength(UInt32(clamping: length)) }
                    let rest = try await withPTPTimeout(.seconds(5), operation: 0) { try await stream.receive(exactly: length - 4) }
                    switch try FujiWiFi.parseInitReply(head + rest) {
                    case .accepted(let name):
                        return FujiWiFiChannel(stream: stream, cameraName: name)
                    case .rejected(let reason):
                        stream.close()
                        // libfuji retries the handshake once.
                        if !rejectedOnce { rejectedOnce = true; lastError = Self.rejection(reason); continue }
                        throw Self.rejection(reason)
                    }
                } catch {
                    stream.close()
                    throw error
                }
            } catch let error as WiFiError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        throw WiFiError.unreachable(String(describing: (lastError as? LocalizedError)?.errorDescription ?? "\(lastError)"))
    }

    private static func rejection(_ reason: UInt32?) -> WiFiError {
        reason == 0x2019 ? .cameraBusy : .rejected(reason)
    }

    func perform(_ command: PTPContainer, outData: Data?, timeout: Duration) async throws -> PTPTransactionResult {
        let stream = self.stream
        return try await withPTPTimeout(timeout, operation: command.code) {
            // Command and data phase in one write.
            var out = try command.encoded()
            if let outData {
                out += try PTPContainer(type: .data, code: command.code, transactionID: command.transactionID, payload: outData).encoded()
            }
            try await stream.send(out)
            var inData = Data()
            while true {
                let c = try await Self.readContainer(stream)
                switch c.type {
                case .data: inData.append(c.payload)
                case .response: return PTPTransactionResult(response: c, inData: inData)
                case .event: continue
                case .command: throw PTPError.unexpectedContainerType(expected: .response, got: c.type.rawValue)
                }
            }
        }
    }

    /// One container: the 12‑byte header, then the body in a single large read.
    static func readContainer(_ stream: TCPStream) async throws -> PTPContainer {
        let header = try await stream.receive(exactly: PTPContainer.headerSize)
        let length = Int(FujiWiFi.integer(header.prefix(4)))
        guard length >= PTPContainer.headerSize, length - PTPContainer.headerSize <= PTPContainer.maxPayload else {
            throw PTPError.invalidLength(UInt32(clamping: length))
        }
        let body = try await stream.receive(exactly: length - PTPContainer.headerSize)
        return try PTPContainer.decode(header + body)
    }

    func close() async {
        try? await stream.send(FujiWiFi.goodbye)
        stream.close()
    }
}

enum WiFiError: Error, Equatable, LocalizedError {
    case unreachable(String)
    case cameraBusy
    case rejected(UInt32?)
    case approvalTimedOut
    case unsupportedCameraState(Int64)
    case noPhotos

    var errorDescription: String? {
        switch self {
        case .unreachable:
            "Couldn't reach the camera over Wi‑Fi. Make sure the iPhone is on the camera's network (FUJIFILM‑…) and the camera's Wi‑Fi screen is open."
        case .cameraBusy: "The camera is busy or connected to another phone. Close XApp, then try again."
        case .rejected(let r): "The camera refused the connection\(r.map { String(format: " (0x%04X)", $0) } ?? "")."
        case .approvalTimedOut: "The camera didn't confirm the connection. Press OK on the camera when it asks, then try again."
        case .unsupportedCameraState(let s):
            s == 6 ? "The camera is in remote-shooting mode. Use PLAYBACK › WIRELESS COMMUNICATION, or connect from FilmLab over Bluetooth."
                : "The camera is in a Wi‑Fi mode FilmLab doesn't support yet (state \(s))."
        case .noPhotos: "There are no photos on the card."
        }
    }
}

/// A browsing/downloading session with one camera, following libfuji's sequence step by step.
actor FujiWiFiSession {
    enum Step: Equatable, Sendable { case handshake, waitingForApproval, ready }

    struct Info: Equatable, Sendable {
        var cameraName: String?
        var mode: FujiWiFi.Mode
        var cameraState: Int64
        var objectCount: Int
        var remoteVersion: Int64
    }

    private let session: PTPSession
    private let channel: FujiWiFiChannel
    private(set) var mode: FujiWiFi.Mode
    private var events: [UInt16: UInt32] = [:]
    private var remoteVersion: Int64 = -1
    private var importCount: Int64 = -1
    private var described: Set<UInt32> = []

    init(channel: FujiWiFiChannel, mode: FujiWiFi.Mode) {
        self.channel = channel
        self.mode = mode
        session = PTPSession(channel: channel)
    }

    /// libfuji `fuji_setup`. `onStep` lets the UI ask the user to press OK on the camera.
    func start(approvalTimeout: Duration = .seconds(90), onStep: @escaping @Sendable (Step) -> Void) async throws -> Info {
        onStep(.handshake)
        try await Task.sleep(for: .milliseconds(50))
        // Transaction ID 1; "already open" is fine.
        try await session.transact(PTPOperation.openSession.rawValue, parameters: [1], accept: [.sessionAlreadyOpen])
        try await poll()
        let clock = ContinuousClock()
        let deadline = clock.now + approvalTimeout
        if events[FujiWiFi.Property.cameraState] ?? 0 == 0 { onStep(.waitingForApproval) }
        while events[FujiWiFi.Property.cameraState] ?? 0 == 0 {
            guard clock.now < deadline else { throw WiFiError.approvalTimedOut }
            try await Task.sleep(for: .milliseconds(100))
            try await poll()
        }
        let cameraState = Int64(events[FujiWiFi.Property.cameraState] ?? 0)
        _ = await integer(FujiWiFi.Property.getObjectVersion)
        _ = await integer(FujiWiFi.Property.remoteGetObjectVersion)
        _ = await integer(FujiWiFi.Property.df21)
        remoteVersion = await integer(FujiWiFi.Property.remoteVersion)
        mode = FujiWiFi.effectiveMode(mode, remoteVersion: remoteVersion)

        guard let client = FujiWiFi.clientState(mode: mode, cameraState: cameraState, remoteVersion: remoteVersion) else {
            throw WiFiError.unsupportedCameraState(cameraState)
        }
        // Newer bodies ask Yes/No on screen here, so this can take as long as the user does.
        onStep(.waitingForApproval)
        try await session.transact(PTPOperation.setDevicePropValue.rawValue, parameters: [UInt32(FujiWiFi.Property.clientState)],
                                   outData: FujiRecipeCodec.u16(client), timeout: approvalTimeout)
        try await poll()

        if mode == .bluetoothHandoff {
            try await bluetoothHandoffSetup()
        } else {
            try await versionHandshake(cameraState: cameraState)
        }
        _ = await integer(FujiWiFi.Property.storageID)
        onStep(.ready)
        return Info(cameraName: channel.cameraName, mode: mode, cameraState: cameraState,
                    objectCount: objectCount, remoteVersion: remoteVersion)
    }

    /// Handles are 1…N; GetObjectHandles isn't used over Wi‑Fi.
    var objectCount: Int {
        let fromEvents = Int(events[FujiWiFi.Property.objectCount] ?? 0)
        return fromEvents > 0 ? fromEvents : max(0, Int(importCount))
    }

    func refreshCount() async throws -> Int {
        try await poll()
        return objectCount
    }

    func objectInfo(_ handle: UInt32) async throws -> FujiObjectInfo {
        let r = try await session.transact(FujiWiFi.Operation.getObjectInfo, parameters: [handle], timeout: .seconds(10))
        described.insert(handle)
        return try FujiObjectInfo.decode(r.inData)
    }

    /// Camera-made JPEG thumbnail. Newer firmware blocks forever unless ObjectInfo came first.
    func thumbnail(_ handle: UInt32) async throws -> Data {
        if remoteVersion > 0x20006, !described.contains(handle) { _ = try await objectInfo(handle) }
        return try await session.transact(FujiWiFi.Operation.getThumb, parameters: [handle], timeout: .seconds(10)).inData
    }

    /// Streams the original file to `url` in 1 MiB GetPartialObject chunks.
    func download(_ handle: UInt32, to url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> FujiObjectInfo {
        if mode == .bluetoothHandoff {
            try? await setU16(FujiWiFi.Property.compression, 2)
        } else {
            try await poll()
            try await setU16(FujiWiFi.Property.noCompression, 1)
        }
        do {
            let info = try await objectInfo(handle)
            let total = Int64(info.compressedSize)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            var offset: Int64 = 0
            while offset < total {
                try Task.checkCancellation()
                let length = UInt32(min(Int64(FujiWiFi.chunkSize), total - offset))
                let r = try await session.transact(FujiWiFi.Operation.getPartialObject,
                                                   parameters: [handle, UInt32(offset), length], timeout: .seconds(20))
                guard !r.inData.isEmpty else { throw PTPError.truncated(needed: Int(length), available: 0) }
                try file.write(contentsOf: r.inData)
                offset += Int64(r.inData.count)
                progress(offset, total)
            }
            try await restoreAfterDownload()
            return info
        } catch {
            try? await restoreAfterDownload()
            throw error
        }
    }

    /// CloseSession, then the goodbye packet (in `FujiWiFiChannel.close`).
    func close() async {
        _ = try? await session.transact(PTPOperation.closeSession.rawValue, timeout: .seconds(2))
        await session.close()
    }

    func diagnostics() async -> [String] { await session.log.map(\.line) }

    // MARK: Steps

    private func restoreAfterDownload() async throws {
        if mode == .bluetoothHandoff {
            try await setU16(FujiWiFi.Property.compression, 2)
        } else {
            try await poll()
            try await setU16(FujiWiFi.Property.noCompression, 0)
        }
    }

    /// libfuji fuji.c L229‑272: echo the version property the camera expects, or announce ours.
    private func versionHandshake(cameraState: Int64) async throws {
        if cameraState == 3 {
            try await echo(FujiWiFi.Property.autoSaveVersion)
        } else if remoteVersion == -1 {
            try await echo(FujiWiFi.Property.getObjectVersion)
        } else {
            try await session.setPropertyValue(FujiWiFi.Property.remoteVersion, FujiRecipeCodec.u32(FujiWiFi.announcedRemoteVersion))
        }
    }

    /// libfuji fuji.c L290‑339 (XApp sequence). Errors that are only response codes are ignored,
    /// as libfuji does.
    private func bluetoothHandoffSetup() async throws {
        try await tolerant { try await self.echo(FujiWiFi.Property.xappDF28) }
        try await tolerant { try await self.setU16(FujiWiFi.Property.compression, 0) }
        try await tolerant { try await self.setU16(FujiWiFi.Property.noCompression, 0) }
        for (op, params) in [(FujiWiFi.Operation.xapp9054, [UInt32(0x1000_0001)]), (FujiWiFi.Operation.xapp9055, [0x1000_0001]),
                             (FujiWiFi.Operation.xapp9050, [])] {
            try await tolerant { try await self.session.transact(op, parameters: params) }
        }
        _ = await integer(FujiWiFi.Property.xappD22B)
        try await tolerant { try await self.session.transact(FujiWiFi.Operation.xapp9053, parameters: [0, 30000], timeout: .seconds(35)) }
        importCount = await integer(FujiWiFi.Property.importObjectCount)
        _ = await integer(FujiWiFi.Property.importObjectHandles)
        try await poll()
    }

    private func tolerant(_ body: @Sendable () async throws -> Void) async throws {
        do { try await body() } catch PTPError.response { }
    }

    private func poll() async throws {
        let data = try await session.getPropertyValue(FujiWiFi.Property.events)
        for (p, v) in try FujiWiFi.parseEvents(data) { events[p] = v }
    }

    private func integer(_ property: UInt16) async -> Int64 {
        FujiWiFi.integer(try? await session.getPropertyValue(property))
    }

    private func echo(_ property: UInt16) async throws {
        let value = try await session.getPropertyValue(property)
        try await session.setPropertyValue(property, value)
    }

    private func setU16(_ property: UInt16, _ value: UInt16) async throws {
        try await session.setPropertyValue(property, FujiRecipeCodec.u16(value))
    }
}
