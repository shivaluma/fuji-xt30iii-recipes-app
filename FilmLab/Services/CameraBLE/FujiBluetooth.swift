import Foundation
import Observation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Bluetooth LE link to a Fujifilm camera: listens for nearby bodies, pairs with one (like
/// FUJIFILM XApp), then answers the camera's clock and location requests and fires the remote
/// shutter. All protocol decisions live in `FujiBLEHandshake`; this class only moves bytes.
///
/// Settings, backups and recipes are never read or written over Bluetooth (docs/wireless.md):
/// the protocol for them isn't published. Recipes install over USB (`CameraController`).
@Observable
@MainActor
final class FujiBluetooth: NSObject {
    struct Sighting: Identifiable, Equatable, Sendable {
        var id: UUID
        var advertisement: FujiBLEAdvertisement
        var rssi: Int?
        /// Connected to this iPhone by another app (e.g. XApp).
        var connectedToPhone: Bool
        var lastSeen: Date
    }

    /// The camera this iPhone paired with through FilmLab.
    struct PairedCamera: Codable, Equatable, Sendable {
        var peripheralID: UUID
        var name: String
        var modelID: String?
        var pairedAt: Date
        var model: CameraModelInfo? { modelID.flatMap(CameraCatalog.info(id:)) ?? CameraCatalog.recognize(name) }
    }

    enum Availability: Equatable, Sendable { case unknown, poweredOff, unauthorized, unsupported, ready }

    enum LinkState: Equatable, Sendable {
        case idle
        case connecting(String)
        /// iOS shows a pairing code; the camera shows the same code.
        case pairing(String)
        case connected(String)
        case failed(String)

        var title: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting…"
            case .pairing: "Confirm the code on both screens"
            case .connected: "Connected over Bluetooth"
            case .failed: "Bluetooth connection failed"
            }
        }
    }

    private(set) var availability: Availability = .unknown
    private(set) var sightings: [Sighting] = []
    private(set) var isScanning = false
    private(set) var link: LinkState = .idle
    private(set) var paired: PairedCamera?
    private(set) var firmware: String?
    private(set) var lastClockSync: Date?
    private(set) var lastLocationSync: Date?
    private(set) var lastShot: Date?
    private(set) var log: [String] = []

    /// Supplies the phone's location when the camera asks (nil = don't share).
    var locationProvider: (@MainActor () -> (latitude: Double, longitude: Double, altitude: Double)?)?

    private let defaults: UserDefaults
    private let clientName: String
    private var wantsScan = false
    /// Set by Disconnect so FilmLab doesn't immediately reconnect to the paired camera.
    private var autoReconnectPaused = false
    private var handshake: FujiBLEHandshake
    private var pendingToken: Data?
    private var queue: [FujiBLEHandshake.Action] = []
    private var inFlight: FujiBLEHandshake.Action?
    // Wi‑Fi handoff awaits individual GATT results.
    private var readWaiters: [String: CheckedContinuation<Data, Error>] = [:]
    private var writeWaiters: [String: CheckedContinuation<Void, Error>] = [:]
    private var readinessWaiter: CheckedContinuation<FujiBLE.WiFiReadiness, Error>?
    #if canImport(CoreBluetooth)
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var servicesPendingDiscovery = 0
    #endif

    init(defaults: UserDefaults = .standard, clientName: String = "FilmLab") {
        self.defaults = defaults
        self.clientName = clientName
        handshake = FujiBLEHandshake(clientName: clientName)
        if let data = defaults.data(forKey: "bluetoothPairedCamera") {
            paired = try? JSONDecoder().decode(PairedCamera.self, from: data)
        }
    }

    var isConnected: Bool { if case .connected = link { true } else { false } }

    /// The closest recognised camera, else the closest Fujifilm one (seen in the last 30 s).
    var best: Sighting? {
        let fresh = sightings.filter { $0.connectedToPhone || Date().timeIntervalSince($0.lastSeen) < 30 }
        return fresh.max { a, b in
            (a.advertisement.model != nil ? 1 : 0, a.connectedToPhone ? 1 : 0, a.rssi ?? -127)
                < (b.advertisement.model != nil ? 1 : 0, b.connectedToPhone ? 1 : 0, b.rssi ?? -127)
        }
    }

    /// A camera advertising PAIRING REGISTRATION (secure) or a legacy token.
    var pairable: Sighting? {
        sightings.filter { $0.advertisement.phase == .pairing || $0.advertisement.token != nil }
            .max { ($0.rssi ?? -127) < ($1.rssi ?? -127) }
    }

    private func note(_ s: String) {
        log.append("\(Date().formatted(date: .omitted, time: .standard))  \(s)")
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    // MARK: Scanning

    func start() {
        wantsScan = true
        #if canImport(CoreBluetooth)
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else {
            beginScanIfReady()
        }
        #else
        availability = .unsupported
        #endif
    }

    func stop() {
        wantsScan = false
        #if canImport(CoreBluetooth)
        central?.stopScan()
        #endif
        isScanning = false
    }

    // MARK: Pairing & connection

    /// Pairs with a camera that's in PAIRING REGISTRATION (or reconnects to the paired one).
    func pair(with sighting: Sighting) {
        #if canImport(CoreBluetooth)
        guard let central, central.state == .poweredOn,
              let p = central.retrievePeripherals(withIdentifiers: [sighting.id]).first else {
            link = .failed("The camera is out of range. Bring it closer and try again.")
            return
        }
        pendingToken = sighting.advertisement.token
        autoReconnectPaused = false
        connect(p, name: sighting.advertisement.model?.name ?? sighting.advertisement.name ?? "camera")
        #endif
    }

    /// Reconnects to the camera paired earlier (it must be on, or set to CONNECT WHILE POWER OFF).
    func reconnect() {
        #if canImport(CoreBluetooth)
        guard let paired, let central, central.state == .poweredOn,
              let p = central.retrievePeripherals(withIdentifiers: [paired.peripheralID]).first else { return }
        pendingToken = nil
        autoReconnectPaused = false
        connect(p, name: paired.model?.name ?? paired.name)
        #endif
    }

    func disconnect() {
        autoReconnectPaused = true
        #if canImport(CoreBluetooth)
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        #endif
        resetLink(.idle)
    }

    /// Forgets the camera in FilmLab. (iOS keeps its own bond: remove it in Settings › Bluetooth.)
    func forget() {
        disconnect()
        paired = nil
        defaults.removeObject(forKey: "bluetoothPairedCamera")
        note("Forgot paired camera")
    }

    /// Remote shutter: press, then release.
    func takePhoto() {
        guard isConnected else { return }
        enqueue(FujiBLEHandshake.takePhoto[0])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            enqueue(FujiBLEHandshake.takePhoto[1])
            lastShot = Date()
        }
    }

    private func resetLink(_ state: LinkState) {
        failWaiters(BluetoothError.disconnected)
        link = state
        queue = []
        inFlight = nil
        handshake = FujiBLEHandshake(clientName: clientName)
        #if canImport(CoreBluetooth)
        characteristics = [:]
        peripheral = nil
        #endif
    }

    // MARK: Wi‑Fi handoff

    struct WiFiCredentials: Equatable, Sendable {
        var ssid: String
        var password: String?
    }

    enum BluetoothError: Error, LocalizedError, Equatable {
        case notConnected, disconnected, unsupported, timedOut, cameraBusy
        var errorDescription: String? {
            switch self {
            case .notConnected: "Connect to the camera over Bluetooth first."
            case .disconnected: "The Bluetooth connection dropped."
            case .unsupported: "This camera doesn't offer starting Wi‑Fi from the phone. Use PLAYBACK › WIRELESS COMMUNICATION on the camera instead."
            case .timedOut: "The camera didn't answer over Bluetooth."
            case .cameraBusy: "The camera couldn't start Wi‑Fi right now. Close any menu on the camera and try again."
            }
        }
    }

    /// Asks the paired camera to start its Wi‑Fi network and returns how to join it
    /// (libfuji `lib/bluetooth.c` L310‑388).
    func wakeWiFi() async throws -> WiFiCredentials {
        guard isConnected else { throw BluetoothError.notConnected }
        #if canImport(CoreBluetooth)
        guard characteristics[FujiBLE.wifiSSID] != nil, characteristics[FujiBLE.wifiStart] != nil else { throw BluetoothError.unsupported }
        #endif
        note("Asking the camera to start Wi‑Fi")
        guard let ssid = FujiBLE.text(try await awaitRead(FujiBLE.wifiSSID)) else { throw BluetoothError.unsupported }
        let readiness = Task { @MainActor in try await self.awaitReadiness(timeout: .seconds(12)) }
        try await awaitWrite(FujiBLE.wifiStart, FujiBLE.wifiStartValue)
        let password = (try? await awaitRead(FujiBLE.wifiPassword)).flatMap(FujiBLE.text)
        switch try? await readiness.value {
        case .busy: throw BluetoothError.cameraBusy
        case .ready: note("Camera Wi‑Fi is up: \(ssid)")
        default: note("No Wi‑Fi confirmation; trying anyway")    // the connect loop retries
        }
        return WiFiCredentials(ssid: ssid, password: password)
    }

    private func awaitRead(_ uuid: String, timeout: Duration = .seconds(6)) async throws -> Data {
        #if canImport(CoreBluetooth)
        guard characteristics[uuid] != nil else { throw BluetoothError.unsupported }
        #endif
        return try await withCheckedThrowingContinuation { c in
            readWaiters[uuid]?.resume(throwing: BluetoothError.timedOut)
            readWaiters[uuid] = c
            enqueue([.read(uuid)])
            expire(after: timeout) { $0.readWaiters.removeValue(forKey: uuid)?.resume(throwing: BluetoothError.timedOut) }
        }
    }

    private func awaitWrite(_ uuid: String, _ value: Data, timeout: Duration = .seconds(6)) async throws {
        #if canImport(CoreBluetooth)
        guard let c = characteristics[uuid] else { throw BluetoothError.unsupported }
        guard c.properties.contains(.write) else { enqueue([.write(uuid, value)]); return }
        #endif
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            writeWaiters[uuid]?.resume(throwing: BluetoothError.timedOut)
            writeWaiters[uuid] = c
            enqueue([.write(uuid, value)])
            expire(after: timeout) { $0.writeWaiters.removeValue(forKey: uuid)?.resume(throwing: BluetoothError.timedOut) }
        }
    }

    private func awaitReadiness(timeout: Duration) async throws -> FujiBLE.WiFiReadiness {
        try await withCheckedThrowingContinuation { c in
            readinessWaiter?.resume(throwing: BluetoothError.timedOut)
            readinessWaiter = c
            expire(after: timeout) { b in
                let w = b.readinessWaiter
                b.readinessWaiter = nil
                w?.resume(throwing: BluetoothError.timedOut)
            }
        }
    }

    private func expire(after timeout: Duration, _ body: @escaping @MainActor (FujiBluetooth) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            if let self { body(self) }
        }
    }

    private func failWaiters(_ error: Error) {
        let reads = readWaiters, writes = writeWaiters, readiness = readinessWaiter
        readWaiters = [:]; writeWaiters = [:]; readinessWaiter = nil
        reads.values.forEach { $0.resume(throwing: error) }
        writes.values.forEach { $0.resume(throwing: error) }
        readiness?.resume(throwing: error)
    }

    // MARK: Action queue (one GATT operation at a time, in order)

    private func enqueue(_ actions: [FujiBLEHandshake.Action]) {
        queue += actions
        pump()
    }

    private func pump() {
        #if canImport(CoreBluetooth)
        while inFlight == nil, !queue.isEmpty {
            let action = queue.removeFirst()
            switch action {
            case .ready:
                completePairing()
            case .fail(let message):
                note("Failed: \(message)")
                if let peripheral { central?.cancelPeripheralConnection(peripheral) }
                resetLink(.failed(message))
                return
            case .read(let uuid):
                guard let c = characteristics[uuid], let peripheral else { continue }
                inFlight = action
                peripheral.readValue(for: c)
            case .write(let uuid, let data):
                guard let c = characteristics[uuid], let peripheral else { continue }
                inFlight = action
                peripheral.writeValue(data, for: c, type: c.properties.contains(.write) ? .withResponse : .withoutResponse)
                if !c.properties.contains(.write) { inFlight = nil }
            case .subscribe(let uuid):
                guard let c = characteristics[uuid], let peripheral,
                      c.properties.contains(.notify) || c.properties.contains(.indicate) else { continue }
                inFlight = action
                peripheral.setNotifyValue(true, for: c)
            }
        }
        #endif
    }

    private func completePairing() {
        #if canImport(CoreBluetooth)
        guard let peripheral else { return }
        let name = peripheral.name ?? paired?.name ?? "Fujifilm camera"
        let record = PairedCamera(peripheralID: peripheral.identifier, name: name,
                                  modelID: CameraCatalog.recognize(name)?.id ?? paired?.modelID,
                                  pairedAt: paired?.peripheralID == peripheral.identifier ? paired?.pairedAt ?? Date() : Date())
        paired = record
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: "bluetoothPairedCamera") }
        link = .connected(record.model?.name ?? name)
        note("Connected and identified as “\(clientName)”")
        #endif
    }

    #if canImport(CoreBluetooth)
    private func connect(_ p: CBPeripheral, name: String) {
        resetLink(.connecting(name))
        peripheral = p
        p.delegate = self
        note("Connecting to \(name)")
        central?.connect(p)
    }

    private func beginScanIfReady() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        let services = FujiBLE.knownServices.map(CBUUID.init(string:))
        for p in central.retrieveConnectedPeripherals(withServices: services) where p.identifier != peripheral?.identifier {
            record(id: p.identifier, advertisement: FujiBLEAdvertisement(name: p.name, phase: .paired, model: p.name.flatMap(CameraCatalog.recognize), token: nil),
                   rssi: nil, connected: true)
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        // The paired camera reconnects on its own when it's in range (iOS keeps the request pending).
        if paired != nil, link == .idle, !autoReconnectPaused { reconnect() }
    }

    private func record(id: UUID, advertisement: FujiBLEAdvertisement, rssi: Int?, connected: Bool) {
        var s = Sighting(id: id, advertisement: advertisement, rssi: rssi, connectedToPhone: connected, lastSeen: Date())
        if let i = sightings.firstIndex(where: { $0.id == id }) {
            s.connectedToPhone = sightings[i].connectedToPhone || connected
            if s.advertisement.model == nil { s.advertisement.model = sightings[i].advertisement.model }
            if s.advertisement.name == nil { s.advertisement.name = sightings[i].advertisement.name }
            // Avoid re-rendering for every advertisement packet with identical content.
            if sightings[i].advertisement != s.advertisement || sightings[i].connectedToPhone != s.connectedToPhone
                || abs((sightings[i].rssi ?? 0) - (s.rssi ?? 0)) > 4 || s.lastSeen.timeIntervalSince(sightings[i].lastSeen) > 5 {
                sightings[i] = s
            }
        } else {
            sightings.append(s)
        }
    }

    private func startHandshake() {
        guard let peripheral else { return }
        let found = Set(characteristics.keys)
        note("Found \(found.count) characteristics")
        let actions = handshake.start(characteristics: found, legacyToken: pendingToken)
        if actions.first == .read(FujiBLE.secureStatus) { link = .pairing(peripheral.name ?? "camera") }
        enqueue(actions)
    }
    #endif
}

#if canImport(CoreBluetooth)
extension FujiBluetooth: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            switch state {
            case .poweredOn: availability = .ready; beginScanIfReady()
            case .poweredOff: availability = .poweredOff; isScanning = false
            case .unauthorized: availability = .unauthorized; isScanning = false
            case .unsupported: availability = .unsupported; isScanning = false
            default: availability = .unknown
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        guard let ad = FujiBLEAdvertisement.parse(localName: name, manufacturerData: data, serviceUUIDs: services) else { return }
        let id = peripheral.identifier
        let rssi = RSSI.intValue == 127 ? nil : RSSI.intValue
        MainActor.assumeIsolated { record(id: id, advertisement: ad, rssi: rssi, connected: false) }
    }

    // The central uses the main queue, so delegate calls already run on the main actor;
    // CoreBluetooth objects aren't Sendable, hence `nonisolated(unsafe)` for the hop.
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated {
            note("Connected; discovering services")
            p.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription ?? "The camera didn't accept the connection."
        MainActor.assumeIsolated { note("Connect failed: \(message)"); resetLink(.failed(message)) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let message = error?.localizedDescription
        let id = peripheral.identifier
        MainActor.assumeIsolated {
            guard self.peripheral?.identifier == id else { return }
            note("Disconnected\(message.map { ": \($0)" } ?? "")")
            if case .pairing = link {
                resetLink(.failed("Pairing didn't finish. Open PAIRING REGISTRATION on the camera and try again."))
            } else {
                resetLink(.idle)
            }
        }
    }
}

extension FujiBluetooth: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        nonisolated(unsafe) let p = peripheral
        MainActor.assumeIsolated {
            let services = p.services ?? []
            servicesPendingDiscovery = services.count
            if services.isEmpty { startHandshake() }
            for s in services { p.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        nonisolated(unsafe) let found = service.characteristics ?? []
        MainActor.assumeIsolated {
            for c in found { characteristics[c.uuid.uuidString.uppercased()] = c }
            servicesPendingDiscovery -= 1
            if servicesPendingDiscovery == 0 { startHandshake() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString.uppercased()
        let value = characteristic.value ?? Data()
        let message = error?.localizedDescription
        MainActor.assumeIsolated {
            let wasRead: Bool = { if case .read(let u) = inFlight, u == uuid { return true }; return false }()
            if wasRead { inFlight = nil }
            if wasRead, let waiter = readWaiters.removeValue(forKey: uuid) {
                if let message { waiter.resume(throwing: BluetoothError.timedOut); note("Read failed: \(message)") }
                else { waiter.resume(returning: value) }
                pump()
                return
            }
            if let message {
                if wasRead && uuid == FujiBLE.secureStatus {
                    // Typically: the user cancelled the iOS pairing dialog.
                    enqueue([.fail("Pairing was cancelled or rejected (\(message)).")])
                }
                pump()
                return
            }
            if wasRead {
                if uuid == FujiBLE.firmwareRevision { firmware = String(decoding: value, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
                enqueue(handshake.didRead(uuid, value: value))
            } else {
                // Notification / indication from the camera.
                if uuid == FujiBLE.indication1, let waiter = readinessWaiter {
                    readinessWaiter = nil
                    waiter.resume(returning: FujiBLE.WiFiReadiness(indication: value))
                }
                let replies = handshake.didNotify(uuid, value: value, now: Date(), location: locationProvider?())
                for case .write(let target, _) in replies {
                    if target == FujiBLE.time { lastClockSync = Date(); note("Camera asked for the time; sent") }
                    if target == FujiBLE.geotag { lastLocationSync = Date(); note("Camera asked for location; sent") }
                }
                enqueue(replies)
            }
            pump()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString.uppercased()
        let message = error?.localizedDescription
        MainActor.assumeIsolated {
            if case .write(let u, _) = inFlight, u == uuid { inFlight = nil }
            if let waiter = writeWaiters.removeValue(forKey: uuid) {
                if let message { waiter.resume(throwing: PTPError.transport(message)) } else { waiter.resume() }
            }
            if let message {
                note("Write to \(uuid.prefix(8)) failed: \(message)")
                if uuid == FujiBLE.secureStatus || uuid == FujiBLE.legacyToken {
                    enqueue([.fail("The camera rejected pairing. Remove FilmLab from the camera's pairing list and pair again.")])
                }
            }
            pump()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString.uppercased()
        MainActor.assumeIsolated {
            if case .subscribe(let u) = inFlight, u == uuid { inFlight = nil }
            pump()
        }
    }
}
#endif
