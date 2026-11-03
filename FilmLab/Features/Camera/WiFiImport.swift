import Foundation
import Observation
import ImageIO
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Wi‑Fi photo import: connect (one tap over Bluetooth, or the camera's WIRELESS COMMUNICATION
/// screen), browse newest-first, and import originals into Photos.
///
/// Where it's quicker than XApp's flow, by design:
///  - Bluetooth wakes the camera's Wi‑Fi and iOS joins it from inside the app — no Settings detour;
///  - connecting retries every 0.4 s while the camera's network comes up, instead of fixed waits;
///  - thumbnails load for what's on screen first, newest photos first;
///  - originals stream in 1 MiB chunks straight to disk and are handed to Photos without
///    re-encoding, while the next file is already downloading;
///  - photos imported before are skipped automatically ("Import New").
@Observable
@MainActor
final class WiFiImport {
    enum Route: String, Equatable, Sendable { case bluetooth, wireless, demo }

    enum Phase: Equatable {
        case idle
        case wakingCamera
        case joiningNetwork(String?)
        case connecting
        case waitingForApproval
        case browsing
        case failed(String)

        var isWorking: Bool {
            switch self { case .wakingCamera, .joiningNetwork, .connecting, .waitingForApproval: true; default: false }
        }
    }

    enum Status: Equatable {
        case new, imported, queued, downloading(Double), saving, failed(String)
        var isPending: Bool { switch self { case .queued, .downloading, .saving: true; default: false } }
    }

    struct Item: Identifiable, Equatable {
        let handle: UInt32
        var info: FujiObjectInfo?
        var thumbnail: CGImage?
        var status: Status = .new
        var id: UInt32 { handle }
        static func == (a: Item, b: Item) -> Bool {
            a.handle == b.handle && a.info == b.info && a.status == b.status && (a.thumbnail == nil) == (b.thumbnail == nil)
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var route: Route?
    private(set) var cameraName: String?
    private(set) var items: [Item] = []
    private(set) var meter: TransferMeter?
    private(set) var importedCount = 0
    /// Current batch: files queued and finished (imported or failed).
    private(set) var batchTotal = 0
    private(set) var batchDone = 0
    private(set) var transferError: String?
    private(set) var log: [String] = []

    private let bluetooth: FujiBluetooth
    private let cacheDirectory: URL
    private var ledger: ImportLedger
    private var session: FujiWiFiSession?
    private var demoCamera: SimulatedWiFiCamera?
    private var joinedSSID: String?
    private var connectTask: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var wake: AsyncStream<Void>.Continuation?
    private var thumbQueue: [UInt32] = []
    private var downloadQueue: [UInt32] = []
    /// Picked by hand: imported again even if the ledger says it's done.
    private var forced: Set<UInt32> = []
    private var index: [UInt32: Int] = [:]
    private var transferStart: ContinuousClock.Instant?
    /// Thumbnails allowed between two downloads, so the grid keeps filling during a big import.
    private var thumbnailBudget = 0

    /// Off in UI tests: files are discarded instead of going to Photos (no permission prompt).
    private let savesToPhotos: Bool

    init(bluetooth: FujiBluetooth, cacheDirectory: URL, ledgerFile: URL?, savesToPhotos: Bool = true) {
        self.bluetooth = bluetooth
        self.savesToPhotos = savesToPhotos
        self.cacheDirectory = cacheDirectory.appendingPathComponent("CameraImports", isDirectory: true)
        ledger = ImportLedger(file: ledgerFile)
    }

    var isConnected: Bool { phase == .browsing }
    var isTransferring: Bool { !downloadQueue.isEmpty || items.contains { $0.status.isPending } }
    var newItems: [Item] { items.filter { $0.status == .new } }
    var isDemo: Bool { route == .demo }

    private func note(_ s: String) {
        log.append("\(Date().formatted(date: .omitted, time: .standard))  \(s)")
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    // MARK: Connect

    func connect(_ route: Route) {
        connectTask?.cancel()
        connectTask = Task { await self.run(route) }
    }

    private func run(_ route: Route) async {
        await teardown()
        self.route = route
        transferError = nil
        do {
            let channel: FujiWiFiChannel
            var mode = FujiWiFi.Mode.wireless
            switch route {
            case .demo:
                phase = .connecting
                let camera = try await SimulatedWiFiCamera.start(photos: SimulatedWiFiCamera.demoRoll(),
                                                                 options: .init(approvalPolls: 8, bytesPerSecond: 6_000_000))
                demoCamera = camera
                channel = try await FujiWiFiChannel.open(host: "127.0.0.1", port: camera.port, clientName: "FilmLab", wifiOnly: false)
            case .bluetooth:
                phase = .wakingCamera
                let credentials = try await bluetooth.wakeWiFi()
                phase = .joiningNetwork(credentials.ssid)
                do {
                    try await CameraHotspot.join(ssid: credentials.ssid, passphrase: credentials.password, hidden: true)
                    joinedSSID = credentials.ssid
                } catch CameraHotspot.JoinError.unavailable {
                    note("In-app join unavailable; expecting the iPhone to be on \(credentials.ssid)")
                }
                phase = .connecting
                mode = .bluetoothHandoff
                channel = try await FujiWiFiChannel.open(clientName: "FilmLab", wifiOnly: true, budget: .seconds(40))
            case .wireless:
                phase = .joiningNetwork(nil)
                do { try await CameraHotspot.joinAnyFujifilm() } catch CameraHotspot.JoinError.unavailable {}
                phase = .connecting
                channel = try await FujiWiFiChannel.open(clientName: "FilmLab", wifiOnly: true, budget: .seconds(20))
            }
            note("Connected\(channel.cameraName.map { " to \($0)" } ?? "")")
            let session = FujiWiFiSession(channel: channel, mode: mode)
            self.session = session
            let info = try await session.start { step in
                Task { @MainActor [weak self] in
                    guard let self, self.phase.isWorking else { return }
                    if step == .waitingForApproval { self.phase = .waitingForApproval }
                }
            }
            cameraName = info.cameraName ?? bluetooth.paired?.model?.name
            note("Session ready (\(info.mode.rawValue), \(info.objectCount) files)")
            try await buildRoll(count: info.objectCount, session: session)
            phase = .browsing
            startWorker()
        } catch is CancellationError {
            await teardown()
            phase = .idle
        } catch {
            note("Failed: \(error)")
            await teardown()
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Handles are 1…N; which end is newest differs by body, so ask the camera rather than assume.
    private func buildRoll(count: Int, session: FujiWiFiSession) async throws {
        guard count > 0 else { items = []; index = [:]; return }
        let first = try await session.objectInfo(1)
        let last = count > 1 ? try await session.objectInfo(UInt32(count)) : first
        let ascending = (first.captureDateString, first.fileName) <= (last.captureDateString, last.fileName)
        let handles = Array(1...UInt32(count))
        let ordered = ascending ? handles.reversed() : handles
        items = ordered.map { Item(handle: $0) }
        index = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.handle, $0) })
        setInfo(first, for: 1)
        if count > 1 { setInfo(last, for: UInt32(count)) }
    }

    func disconnect() {
        connectTask?.cancel()
        Task { await teardown(); phase = .idle }
    }

    private func teardown() async {
        worker?.cancel(); worker = nil
        wake?.finish(); wake = nil
        thumbQueue = []; downloadQueue = []
        for i in items.indices where items[i].status.isPending { items[i].status = .new }
        if let session { await session.close() }
        session = nil
        demoCamera?.stop(); demoCamera = nil
        if let joinedSSID { CameraHotspot.leave(ssid: joinedSSID) }
        joinedSSID = nil
        meter = nil
        setIdleTimer(disabled: false)
    }

    // MARK: Requests from the grid

    func requestThumbnail(_ handle: UInt32) {
        guard let i = index[handle], items[i].thumbnail == nil, isConnected else { return }
        thumbQueue.removeAll { $0 == handle }
        thumbQueue.append(handle)                 // LIFO: what just scrolled into view first
        wake?.yield()
    }

    func cancelThumbnail(_ handle: UInt32) { thumbQueue.removeAll { $0 == handle } }

    func importNew() { enqueue(newItems.map(\.handle)) }

    func importSelection(_ handles: Set<UInt32>) {
        let picked = items.filter { handles.contains($0.handle) && !$0.status.isPending }.map(\.handle)
        forced.formUnion(picked)
        enqueue(picked)
    }

    /// Stops after the file in flight (cancelling mid-transaction would desync the PTP stream).
    func cancelTransfers() {
        for h in downloadQueue { if let i = index[h] { items[i].status = .new } }
        batchTotal -= downloadQueue.count
        downloadQueue = []
    }

    private func enqueue(_ handles: [UInt32]) {
        guard !handles.isEmpty, isConnected else { return }
        Task {
            do { if savesToPhotos { try await PhotoLibrarySaver.ensureAccess() } } catch {
                transferError = error.localizedDescription
                return
            }
            if !isTransferring { batchTotal = 0; batchDone = 0; meter = TransferMeter(totalBytes: 0); transferStart = .now }
            for h in handles where !downloadQueue.contains(h) {
                downloadQueue.append(h)
                batchTotal += 1
                if let i = index[h] { items[i].status = .queued }
            }
            setIdleTimer(disabled: true)
            wake?.yield()
        }
    }

    // MARK: Worker — one PTP transaction at a time, downloads before thumbnails

    private func startWorker() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        worker = Task { [weak self] in
            for await _ in stream {
                while let self, !Task.isCancelled, let job = self.nextJob() {
                    await self.perform(job)
                }
            }
        }
        continuation.yield()
    }

    private enum Job { case download(UInt32), thumbnail(UInt32) }

    private func nextJob() -> Job? {
        if thumbnailBudget > 0, let h = thumbQueue.popLast() { thumbnailBudget -= 1; return .thumbnail(h) }
        if !downloadQueue.isEmpty { thumbnailBudget = 4; return .download(downloadQueue.removeFirst()) }
        if let h = thumbQueue.popLast() { return .thumbnail(h) }
        if downloadQueue.isEmpty, items.allSatisfy({ !$0.status.isPending }) { setIdleTimer(disabled: false) }
        return nil
    }

    private func perform(_ job: Job) async {
        guard let session else { return }
        switch job {
        case .thumbnail(let h):
            do {
                if index[h].map({ items[$0].info == nil }) == true { setInfo(try await session.objectInfo(h), for: h) }
                let data = try await session.thumbnail(h)
                if let i = index[h] { items[i].thumbnail = Self.decode(data) }
            } catch {
                handleTransportError(error)
            }
        case .download(let h):
            // "Import New" decides on the camera's file details, never on a guess.
            if !forced.contains(h), let i = index[h] {
                if items[i].info == nil, let info = try? await session.objectInfo(h) { setInfo(info, for: h) }
                if let key = ledgerKey(items[i]), ledger.contains(key) {
                    items[i].status = .imported
                    batchDone += 1
                    return
                }
            }
            forced.remove(h)
            await download(h, session: session)
        }
    }

    private func download(_ h: UInt32, session: FujiWiFiSession) async {
        guard let i = index[h] else { return }
        let name = items[i].info?.fileName ?? "DSCF\(h).JPG"
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let url = cacheDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        items[i].status = .downloading(0)
        let progress = ProgressRelay { [weak self] delta, done, total in
            guard let self, let i = self.index[h] else { return }
            self.items[i].status = .downloading(total > 0 ? Double(done) / Double(total) : 0)
            self.meter?.totalBytes += delta.newTotal
            self.meter?.add(delta.bytes, at: self.elapsed)
        }
        do {
            let info = try await session.download(h, to: url) { done, total in progress.send(done: done, total: total) }
            setInfo(info, for: h)
            items[i].status = .saving
            // Hand off to Photos without blocking the next download.
            Task { [weak self] in
                do {
                    if self?.savesToPhotos == false { try? FileManager.default.removeItem(at: url) }
                    else { try await PhotoLibrarySaver.save(fileURL: url, originalFileName: info.fileName) }
                    guard let self, let i = self.index[h] else { return }
                    self.items[i].status = .imported
                    self.importedCount += 1
                    self.batchDone += 1
                    if let key = self.ledgerKey(self.items[i]) { self.ledger.insert(key) }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    guard let self, let i = self.index[h] else { return }
                    self.items[i].status = .failed(error.localizedDescription)
                    self.transferError = error.localizedDescription
                    self.batchDone += 1
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            if let i = index[h] { items[i].status = error is CancellationError ? .new : .failed((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            batchDone += 1
            handleTransportError(error)
        }
    }

    private var elapsed: TimeInterval {
        guard let transferStart else { return 0 }
        return Double((ContinuousClock.now - transferStart) / .milliseconds(1)) / 1000
    }

    private func handleTransportError(_ error: Error) {
        guard let e = error as? PTPError else { return }
        switch e {
        case .disconnected, .transport, .timeout:
            note("Lost the camera: \(e)")
            Task { await teardown(); phase = .failed("The camera's Wi‑Fi connection dropped. Reconnect to continue — finished photos are already in Photos.") }
        default:
            break
        }
    }

    private func setInfo(_ info: FujiObjectInfo, for handle: UInt32) {
        guard let i = index[handle] else { return }
        var info = info
        if info.compressedSize == 100 * 1024, items[i].info == nil { info.compressedSize = 0 }
        items[i].info = info
        if items[i].status == .new, let key = ledgerKey(items[i]), ledger.contains(key) { items[i].status = .imported }
    }

    private func ledgerKey(_ item: Item) -> String? {
        guard let info = item.info else { return nil }
        return ImportLedger.key(camera: cameraName ?? "camera", fileName: info.fileName, captureDate: info.captureDateString)
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit) && !FILMLAB_CLI
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// Forwards chunk progress from the session actor to the main actor, coalesced per chunk.
private final class ProgressRelay: @unchecked Sendable {
    struct Delta { var bytes: Int64; var newTotal: Int64 }
    private let lock = NSLock()
    private var lastDone: Int64 = 0
    private var knownTotal: Int64 = 0
    private let apply: @MainActor (Delta, Int64, Int64) -> Void

    init(_ apply: @escaping @MainActor (Delta, Int64, Int64) -> Void) { self.apply = apply }

    func send(done: Int64, total: Int64) {
        let delta: Delta = lock.withLock {
            let d = Delta(bytes: done - lastDone, newTotal: knownTotal == 0 ? total : 0)
            lastDone = done
            knownTotal = total
            return d
        }
        Task { @MainActor in apply(delta, done, total) }
    }
}
