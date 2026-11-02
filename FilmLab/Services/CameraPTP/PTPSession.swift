import Foundation

/// The lowest-level abstraction: perform one complete PTP transaction.
///
/// Implementations: `ImageCapturePTPChannel` (real hardware via ImageCaptureCore) and
/// `SimulatedFujiCamera` (in-memory emulator for demo mode and tests). Everything above this
/// protocol — session handling, codec, slot reads/writes — is shared, so the demo exercises the
/// same code paths that will talk to real hardware.
protocol PTPCommandChannel: Sendable {
    /// - Parameters:
    ///   - command: a fully formed command container (type `.command`, transaction ID set).
    ///   - outData: data-out phase payload (no container header), if the operation sends data.
    func perform(_ command: PTPContainer, outData: Data?, timeout: Duration) async throws -> PTPTransactionResult
    func close() async
    /// False when the transport (e.g. ImageCaptureCore) assigns its own transaction IDs, so the
    /// response cannot be expected to echo ours.
    var echoesTransactionIDs: Bool { get }
}

/// FIFO async mutex. Swift actors are re-entrant across `await`, so an actor alone does not
/// guarantee one-transaction-at-a-time; this gate does.
actor AsyncSerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }
}

/// Runs `operation` with a deadline. Throws `PTPError.timeout` if it doesn't finish in time.
func withPTPTimeout<T: Sendable>(_ timeout: Duration, operation: UInt16, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw PTPError.timeout(operation: operation)
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw PTPError.cancelled }
        return first
    }
}

/// Owns transaction IDs and validates every response. Strictly one transaction at a time.
actor PTPSession {
    private let channel: PTPCommandChannel
    private let gate = AsyncSerialGate()
    private var nextTransactionID: UInt32 = 1
    private(set) var isOpen = false
    private(set) var log: [PTPLogEntry] = []
    var defaultTimeout: Duration = .seconds(5)

    init(channel: PTPCommandChannel) {
        self.channel = channel
    }

    struct PTPLogEntry: Sendable, Identifiable {
        let id = UUID()
        let date: Date
        let operation: UInt16
        let parameters: [UInt32]
        let outBytes: Int
        let inBytes: Int
        let response: UInt16?
        let durationMs: Int
        let error: String?

        /// Redacted one-line description: never includes payload bytes.
        var line: String {
            let params = parameters.map { String(format: "0x%X", $0) }.joined(separator: ",")
            let resp = response.map { String(format: "0x%04X", $0) } ?? "—"
            return String(format: "op 0x%04X [%@] out=%dB in=%dB resp=%@ %dms", operation, params, outBytes, inBytes, resp, durationMs)
                + (error.map { " ERR \($0)" } ?? "")
        }
    }

    private func allocateTransactionID() -> UInt32 {
        defer {
            nextTransactionID &+= 1
            if nextTransactionID == 0 || nextTransactionID == 0xFFFF_FFFF { nextTransactionID = 1 }
        }
        return nextTransactionID
    }

    /// Performs and validates one transaction. Throws `PTPError.response` for non-OK codes
    /// unless the code is in `accept`.
    @discardableResult
    func transact(_ operation: UInt16, parameters: [UInt32] = [], outData: Data? = nil,
                  timeout: Duration? = nil, accept: Set<PTPResponseCode> = []) async throws -> PTPTransactionResult {
        try Task.checkCancellation()
        let channel = self.channel
        let tid = allocateTransactionID()
        let command = PTPContainer.command(operation, transactionID: tid, parameters: parameters)
        let limit = timeout ?? defaultTimeout
        let start = ContinuousClock.now
        do {
            let result = try await gate.run {
                try await channel.perform(command, outData: outData, timeout: limit)
            }
            guard result.response.type == .response else {
                throw PTPError.unexpectedContainerType(expected: .response, got: result.response.type.rawValue)
            }
            if channel.echoesTransactionIDs, result.response.transactionID != tid {
                throw PTPError.transactionMismatch(expected: tid, got: result.response.transactionID)
            }
            record(operation, parameters, outData, result, start, nil)
            let code = result.responseCode
            if code != .ok, !accept.contains(code) { throw PTPError.response(code, operation: operation) }
            return result
        } catch {
            record(operation, parameters, outData, nil, start, error)
            throw error
        }
    }

    private func record(_ op: UInt16, _ params: [UInt32], _ out: Data?, _ result: PTPTransactionResult?, _ start: ContinuousClock.Instant, _ error: Error?) {
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        log.append(PTPLogEntry(date: Date(), operation: op, parameters: params, outBytes: out?.count ?? 0,
                               inBytes: result?.inData.count ?? 0, response: result?.response.code,
                               durationMs: ms, error: error.map { String(describing: $0) }))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    // MARK: Standard operations

    func open(sessionID: UInt32 = 1) async throws {
        let r = try await transact(PTPOperation.openSession.rawValue, parameters: [sessionID], accept: [.sessionAlreadyOpen])
        if r.responseCode == .sessionAlreadyOpen {
            // reshipi: close and retry once.
            _ = try? await transact(PTPOperation.closeSession.rawValue)
            try await transact(PTPOperation.openSession.rawValue, parameters: [sessionID])
        }
        isOpen = true
    }

    func close() async {
        if isOpen { _ = try? await transact(PTPOperation.closeSession.rawValue, timeout: .seconds(2)) }
        isOpen = false
        await channel.close()
    }

    func deviceInfo() async throws -> PTPDeviceInfo {
        let r = try await transact(PTPOperation.getDeviceInfo.rawValue)
        return try PTPDeviceInfo.decode(r.inData)
    }

    func getPropertyValue(_ code: UInt16) async throws -> Data {
        try await transact(PTPOperation.getDevicePropValue.rawValue, parameters: [UInt32(code)]).inData
    }

    func setPropertyValue(_ code: UInt16, _ value: Data) async throws {
        try await transact(PTPOperation.setDevicePropValue.rawValue, parameters: [UInt32(code)], outData: value)
    }
}
