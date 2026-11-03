import Foundation
import Network

/// A TCP byte stream over Network.framework with exact-length reads. Tuned for bulk photo
/// transfer from a camera's own access point:
///  - bound to Wi‑Fi (`requiredInterfaceType`), so iOS doesn't route around a hotspot that has
///    no internet through cellular;
///  - Nagle off, so small PTP commands go out immediately;
///  - reads ask for the whole remaining length in one call, so a multi‑megabyte data phase
///    arrives in a few large callbacks instead of many small ones.
final class TCPStream: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "app.filmlab.tcp", qos: .userInitiated)

    private init(_ connection: NWConnection) { self.connection = connection }

    /// Connects, failing after `timeout`. `wifiOnly` is off for loopback (tests, demo camera).
    static func connect(host: String, port: UInt16, wifiOnly: Bool, timeout: Duration) async throws -> TCPStream {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = max(1, Int(timeout.components.seconds))
        let params = NWParameters(tls: nil, tcp: tcp)
        if wifiOnly { params.requiredInterfaceType = .wifi }
        params.serviceClass = .responsiveData
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw PTPError.transport("Invalid port \(port).") }
        let stream = TCPStream(NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params))
        try await stream.start(timeout: timeout)
        return stream
    }

    /// Wraps a connection accepted by an `NWListener` (the emulated camera's side).
    static func accepted(_ connection: NWConnection) async throws -> TCPStream {
        let stream = TCPStream(connection)
        try await stream.start(timeout: .seconds(5))
        return stream
    }

    private func start(timeout: Duration) async throws {
        let once = OnceFlag()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { [connection] state in
                    switch state {
                    case .ready:
                        if once.claim() { c.resume() }
                    case .failed(let e):
                        if once.claim() { c.resume(throwing: PTPError.transport(e.localizedDescription)) }
                    case .waiting(let e):
                        // No route yet (e.g. the camera's network is still coming up): fail fast so
                        // the caller can retry on its own schedule instead of NWConnection's.
                        if once.claim() { connection.cancel(); c.resume(throwing: PTPError.transport(e.localizedDescription)) }
                    case .cancelled:
                        if once.claim() { c.resume(throwing: PTPError.cancelled) }
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout / .milliseconds(1)))) { [connection] in
                    if once.claim() { connection.cancel(); c.resume(throwing: PTPError.transport("Connection timed out.")) }
                }
            }
        } onCancel: { [connection] in
            connection.cancel()
        }
        connection.stateUpdateHandler = { [connection] state in
            if case .failed = state { connection.cancel() }
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { c.resume(throwing: PTPError.transport(error.localizedDescription)) } else { c.resume() }
            })
        }
    }

    /// Reads exactly `count` bytes (or throws `.disconnected` if the peer closes first).
    func receive(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            try Task.checkCancellation()
            let want = count - buffer.count
            let chunk: Data = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: want) { data, _, isComplete, error in
                        if let error { c.resume(throwing: PTPError.transport(error.localizedDescription)) }
                        else if let data, !data.isEmpty { c.resume(returning: data) }
                        else if isComplete { c.resume(throwing: PTPError.disconnected) }
                        else { c.resume(returning: Data()) }
                    }
                }
            } onCancel: { [connection] in
                connection.cancel()
            }
            buffer.append(chunk)
        }
        return buffer
    }

    func close() { connection.cancel() }
}

/// Thread-safe "first caller wins".
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Bytes-per-second and time-left for a transfer, smoothed over a sliding window so the
/// numbers don't jump with every chunk. Pure; unit-tested.
struct TransferMeter: Sendable, Equatable {
    var totalBytes: Int64
    private(set) var doneBytes: Int64 = 0
    private var samples: [(t: TimeInterval, bytes: Int64)] = []
    var window: TimeInterval = 3

    init(totalBytes: Int64) { self.totalBytes = totalBytes }

    static func == (a: TransferMeter, b: TransferMeter) -> Bool { a.totalBytes == b.totalBytes && a.doneBytes == b.doneBytes }

    mutating func add(_ bytes: Int64, at t: TimeInterval) {
        doneBytes += bytes
        samples.append((t, doneBytes))
        while let first = samples.first, t - first.t > window, samples.count > 2 { samples.removeFirst() }
    }

    var fraction: Double { totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : 0 }

    var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last, last.t - first.t >= 0.2 else { return nil }
        return Double(last.bytes - first.bytes) / (last.t - first.t)
    }

    var secondsLeft: Double? {
        guard let rate = bytesPerSecond, rate > 0 else { return nil }
        return Double(max(0, totalBytes - doneBytes)) / rate
    }

    /// "12.4 MB/s"
    var rateLabel: String? {
        bytesPerSecond.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + "/s" }
    }
}
