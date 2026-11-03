import Foundation
import Observation
import os
#if canImport(ImageCaptureCore)
import ImageCaptureCore
#endif

/// Everything needed to write one slot, computed BEFORE the user confirms.
struct SlotWritePlan: Identifiable, Sendable {
    var id: CameraSlot { slot }
    var slot: CameraSlot
    var recipeID: UUID
    var recipeName: String
    var slotName: String
    var settings: RecipeSettings
    /// The camera this plan was reviewed against. `execute` refuses a plan for another body.
    var camera: CameraIdentity
    var before: CameraSlotSnapshot?
    var diff: [SettingDiffRow]
    var issues: [ValidationIssue]
    var backupID: UUID?

    var hasBlockingIssues: Bool { issues.contains { $0.severity == .error } }
    var changedCount: Int { diff.filter { $0.kind == .changed }.count }
}

enum SlotWriteOutcome: Equatable, Sendable {
    case pending
    case writing
    case verified
    case mismatched([String])
    case failed(String)
    /// Interrupted mid-write: the slot must be re-read before anything is assumed.
    case unknown(String)
    case skipped
    case stopped

    var label: String {
        switch self {
        case .pending: "Pending"
        case .writing: "Writing…"
        case .verified: "Written & verified"
        case .mismatched(let m): "Read-back mismatch (\(m.count))"
        case .failed: "Failed"
        case .unknown: "Outcome unknown · verify camera"
        case .skipped: "Skipped"
        case .stopped: "Stopped before writing"
        }
    }

    var isTerminal: Bool { self != .pending && self != .writing }
}

/// Camera connection state machine + guarded read/backup/write flows.
/// Previewing never touches this object; every write requires an explicit plan + confirmation.
@Observable
@MainActor
final class CameraController {
    enum Mode: Equatable { case none, demo, usb }

    private(set) var state: CameraConnectionState = .disconnected
    private(set) var mode: Mode = .none
    private(set) var snapshots: [CameraSlot: CameraSlotSnapshot] = [:]
    private(set) var backups: [CameraBackup] = []
    private(set) var sessionBackupID: UUID?
    private(set) var activity: String?
    private(set) var lastError: String?
    /// Slots whose last write outcome is unknown; re-read automatically after reconnect.
    private(set) var slotsNeedingVerification: Set<CameraSlot> = []
    private(set) var setOutcomes: [CameraSlot: SlotWriteOutcome] = [:]
    private(set) var isInstallingSet = false
    private var stopRequested = false
    /// Set when the user taps Disconnect, so the Camera tab stops looking for cameras until asked.
    private(set) var autoDetectPaused = false

    let settings: AppSettings
    let backupStore: CameraBackupStore
    /// Profile of the connected body (catalog); the X-T30 III reference profile when disconnected.
    private(set) var profile = CameraProfile.xt30III
    private(set) var transport: CameraTransport?
    private(set) var demoCamera: SimulatedFujiCamera?
    private let writeGate = OSAllocatedUnfairLock(initialState: false)
    #if canImport(ImageCaptureCore)
    private var browser: ImageCaptureCameraBrowser?
    #endif
    private let logger = Logger(subsystem: "app.filmlab", category: "camera")

    init(settings: AppSettings, backupStore: CameraBackupStore) {
        self.settings = settings
        self.backupStore = backupStore
        self.backups = backupStore.loadAll()
    }

    var identity: CameraIdentity? { state.identity }
    var isDemo: Bool { mode == .demo }
    private var busyCount = 0
    private var isAttaching = false
    #if canImport(ImageCaptureCore)
    private var usbDevice: ICCameraDevice?
    #endif

    static func sameCamera(_ a: CameraIdentity, _ b: CameraIdentity) -> Bool {
        a.model == b.model && a.serialHash == b.serialHash && a.isDemo == b.isDemo
    }

    // MARK: Connection

    func connectDemo() async {
        await disconnect()
        mode = .demo
        state = .searching
        let camera = SimulatedFujiCamera()
        demoCamera = camera
        writeGate.withLock { $0 = true } // demo camera writes are harmless (in-memory)
        let gate = writeGate
        let t = FujiPTPCameraTransport(channel: camera, kind: .demo, opensPTPSession: true,
                                       writesEnabled: { gate.withLock { $0 } })
        await attach(t)
    }

    /// Starts looking for a USB camera (unless the user paused it), so plugging one in is
    /// recognised without tapping Connect. Identifying a body only reads its device info;
    /// slots are never read or written automatically.
    func autoDetect() async {
        #if canImport(ImageCaptureCore)
        guard ImageCaptureCameraBrowser.isSupported else { return }
        #endif
        guard mode == .none, state == .disconnected, !autoDetectPaused else { return }
        await startUSB()
    }

    /// Disconnect from the UI: also pauses automatic detection.
    func disconnectByUser() async {
        await disconnect()
        autoDetectPaused = true
    }

    func startUSB() async {
        #if canImport(ImageCaptureCore)
        await disconnect()
        guard ImageCaptureCameraBrowser.isSupported else {
            state = .failed("USB cameras can't connect in the iOS Simulator. Use the Demo Camera, or run FilmLab on an iPhone.")
            return
        }
        autoDetectPaused = false
        mode = .usb
        state = .searching
        let b = ImageCaptureCameraBrowser()
        browser = b
        b.onEvent = { [weak self] event in self?.handle(event) }
        await b.start()
        #else
        state = .failed("USB cameras aren't available on this platform.")
        #endif
    }

    #if canImport(ImageCaptureCore)
    private func handle(_ event: ImageCaptureCameraBrowser.Event) {
        switch event {
        case .authorization(let s):
            switch s {
            case .denied, .restricted: state = .permissionDenied
            case .notDetermined: state = .permissionNeeded
            case .authorized, .notRequired: if case .searching = state {} else { state = .searching }
            }
        case .found(let device):
            // One attach at a time; `transport` stays nil until the attach completes.
            guard transport == nil, !isAttaching else { return }
            isAttaching = true
            Task {
                await self.attachUSB(device)
                self.isAttaching = false
            }
        case .removed(let device):
            if let current = usbDevice, current === device {
                handleUnexpectedDisconnect()
            } else if transport == nil, !isAttaching {
                // A released camera (profile only, unsupported, wrong mode) was unplugged: keep looking.
                switch state {
                case .profileOnly, .unsupportedModel, .wrongMode, .failed, .connected: state = .searching
                default: break
                }
            }
        case .sessionError(let m):
            state = .failed(m)
        }
    }

    private func attachUSB(_ device: ICCameraDevice) async {
        guard let browser else { return }
        state = .connected(CameraIdentity(manufacturer: "", model: device.name ?? "Camera", firmwareVersion: nil, serialHash: nil, isDemo: false))
        do {
            try await browser.openSession(device)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        usbDevice = device
        let gate = writeGate
        let allowWrites = settings.experimentalSlotWrites
        writeGate.withLock { $0 = allowWrites }
        let channel = ImageCapturePTPChannel(device: device)
        let t = FujiPTPCameraTransport(channel: channel, kind: .imageCaptureUSB, opensPTPSession: false,
                                       writesEnabled: { gate.withLock { $0 } })
        await attach(t)
        if transport == nil { await closeUSBSession() } // attach failed: release the camera
    }

    private func closeUSBSession() async {
        if let device = usbDevice, let browser { await browser.closeSession(device) }
        usbDevice = nil
    }
    #endif

    #if DEBUG || FILMLAB_CLI
    /// Tests: attach an arbitrary transport (e.g. a simulated body with another model name).
    func attachForTesting(_ t: CameraTransport) async {
        await disconnect()
        mode = .demo
        await attach(t)
    }
    #endif

    private func attach(_ t: CameraTransport) async {
        do {
            let id = try await t.connect()
            guard let body = CameraCatalog.recognize(id.model) else {
                await t.disconnect()
                state = .unsupportedModel(id.model)
                return
            }
            profile = body.profile
            guard body.profile.allowsSlotWrites else {
                // Recognised, but nobody has reported FilmLab's PTP slot map working on this body.
                // Even reading selects a slot over PTP, so release the camera and show the profile only.
                await t.disconnect()
                state = .profileOnly(id)
                logger.info("Camera recognised (profile only): \(id.model, privacy: .public)")
                return
            }
            transport = t
            refreshWritability(id)
            logger.info("Camera connected: \(id.model, privacy: .public) fw \(id.firmwareVersion ?? "?", privacy: .public)")
            if !slotsNeedingVerification.isEmpty {
                await read(Array(slotsNeedingVerification).sorted())
            }
        } catch let e as CameraError {
            await t.disconnect()
            switch e {
            case .wrongMode(let m): state = .wrongMode(m)
            case .unsupportedModel(let m): state = .unsupportedModel(m)
            case .permissionDenied: state = .permissionDenied
            default: state = .failed(e.localizedDescription)
            }
        } catch {
            await t.disconnect()
            state = .failed(error.localizedDescription)
        }
    }

    /// Re-evaluates read-only vs writable (e.g. after the Settings toggle changes).
    func refreshWritability(_ id: CameraIdentity? = nil) {
        guard transport != nil, let id = id ?? identity else { return }
        let writable = (mode == .demo || settings.experimentalSlotWrites) && profile.allowsSlotWrites
        let allowWrites = settings.experimentalSlotWrites
        if mode == .usb { writeGate.withLock { $0 = allowWrites } }
        if busyCount > 0, let what = activity { state = .busy(id, what); return }
        state = writable ? .readyWritable(id) : .readyReadOnly(id)
    }

    func disconnect() async {
        if let t = transport { await t.disconnect() }
        transport = nil
        demoCamera = nil
        #if canImport(ImageCaptureCore)
        await closeUSBSession()
        browser?.stop()
        browser = nil
        #endif
        mode = .none
        state = .disconnected
        profile = .xt30III
        resetPerConnectionState()
        setOutcomes = [:]
    }

    /// Anything read or reviewed belongs to one connection; never carry it over to the next.
    private func resetPerConnectionState() {
        activity = nil
        busyCount = 0
        snapshots = [:]
        sessionBackupID = nil
    }

    private func handleUnexpectedDisconnect() {
        transport = nil
        #if canImport(ImageCaptureCore)
        usbDevice = nil
        #endif
        state = .disconnected
        #if canImport(ImageCaptureCore)
        // Still browsing: plugging the camera back in reconnects it.
        if mode == .usb, browser != nil { state = .searching }
        #endif
        resetPerConnectionState()
        if isInstallingSet { stopRequested = true }
    }

    // MARK: Reads & backups

    private func setBusy(_ what: String) {
        busyCount += 1
        activity = what
        if let id = identity { state = .busy(id, what) }
    }

    private func clearBusy() {
        busyCount = max(0, busyCount - 1)
        guard busyCount == 0 else { return }
        activity = nil
        if let id = identity { refreshWritability(id) }
    }

    @discardableResult
    func readAllSlots() async -> Bool { await read(CameraSlot.allCases) }

    /// Returns true only if every requested slot was read successfully just now.
    @discardableResult
    func read(_ slots: [CameraSlot]) async -> Bool {
        guard let t = transport else { lastError = CameraError.notConnected.localizedDescription; return false }
        setBusy("Reading \(slots.count == 7 ? "C1–C7" : slots.map(\.label).joined(separator: ", "))")
        defer { clearBusy() }
        do {
            let fresh = try await t.readSlots(slots)
            guard transport === t else { return false } // disconnected/replaced meanwhile
            for s in fresh {
                snapshots[s.slot] = s
                slotsNeedingVerification.remove(s.slot)
            }
            lastError = nil
            return Set(fresh.map(\.slot)) == Set(slots)
        } catch {
            lastError = error.localizedDescription
            if case CameraError.ptp(.disconnected) = error { handleUnexpectedDisconnect() }
            return false
        }
    }

    /// Reads all seven slots and stores a timestamped local backup. Fails rather than back up
    /// anything that wasn't read in this call.
    @discardableResult
    func backupAll(reason: String) async -> CameraBackup? {
        let started = Date()
        guard await readAllSlots(), let id = identity else {
            lastError = lastError ?? "Backup incomplete: not every slot could be read."
            return nil
        }
        let fresh = CameraSlot.allCases.compactMap { snapshots[$0] }.filter { $0.readAt >= started }
        guard fresh.count == CameraSlot.allCases.count else {
            lastError = "Backup incomplete: not every slot could be read."
            return nil
        }
        let backup = CameraBackup(createdAt: Date(), camera: id, reason: reason, snapshots: fresh)
        do {
            _ = try backupStore.save(backup)
            backups.insert(backup, at: 0)
            sessionBackupID = backup.id
            return backup
        } catch {
            lastError = "Couldn't save backup: \(error.localizedDescription)"
            return nil
        }
    }

    func exportURL(for backup: CameraBackup) -> URL? { backupStore.fileURL(for: backup) }

    func deleteBackup(_ backup: CameraBackup) {
        backupStore.delete(backup)
        backups.removeAll { $0.id == backup.id }
    }

    // MARK: Writes

    /// Reads the target slot fresh, ensures a backup exists for this connection, and builds the
    /// diff. Performs NO writes.
    func prepareWrite(recipe: FilmRecipe, slot: CameraSlot, slotName: String? = nil) async throws -> SlotWritePlan {
        guard transport != nil else { throw CameraError.notConnected }
        if sessionBackupID == nil {
            guard await backupAll(reason: "Automatic backup before writing \(slot.label)") != nil else {
                throw CameraError.encoding(lastError ?? "Backup failed; nothing was written.")
            }
        } else {
            guard await read([slot]) else {
                throw CameraError.encoding(lastError ?? "Couldn't read \(slot.label); nothing was written.")
            }
        }
        guard let camera = identity else { throw CameraError.notConnected }
        let name = slotName ?? FujiRecipeCodec.suggestedSlotName(for: recipe.name)
        var issues = RecipeValidator(profile: profile).validate(recipe.settings)
        do { _ = try FujiRecipeCodec.validatedSlotName(name) } catch {
            issues.append(.init(key: .filmSimulation, severity: .error, message: error.localizedDescription))
        }
        return SlotWritePlan(slot: slot, recipeID: recipe.id, recipeName: recipe.name, slotName: name,
                             settings: recipe.settings.normalized(), camera: camera, before: snapshots[slot],
                             diff: SlotDiff.rows(before: snapshots[slot]?.settings, new: recipe.settings),
                             issues: issues, backupID: sessionBackupID)
    }

    /// Executes a confirmed plan: guarded write → read-back → exact mismatch report.
    func execute(_ plan: SlotWritePlan) async -> SlotWriteOutcome {
        guard let t = transport, let current = identity else { return .failed(CameraError.notConnected.localizedDescription) }
        guard Self.sameCamera(plan.camera, current) else {
            return .failed("This review was made for a different camera connection. Review the changes again.")
        }
        guard state.canWrite else { return .failed(CameraError.writesDisabled.localizedDescription) }
        guard !plan.hasBlockingIssues else { return .failed("Fix the highlighted settings before writing.") }
        guard let backupID = plan.backupID, backupID == sessionBackupID,
              let backup = backups.first(where: { $0.id == backupID }), Self.sameCamera(backup.camera, current) else {
            return .failed("No backup of this camera exists for this connection; nothing was written.")
        }
        setBusy("Writing \(plan.slot.label)")
        defer { clearBusy() }
        do {
            let report = try await t.writeSlot(plan.slot, settings: plan.settings, name: plan.slotName)
            snapshots[plan.slot] = report.after
            logger.info("Wrote \(plan.slot.label, privacy: .public): \(report.mismatches.count) mismatches")
            return report.mismatches.isEmpty ? .verified : .mismatched(report.mismatches.map(\.description))
        } catch CameraError.outcomeUnknown(let slot, let message) {
            slotsNeedingVerification.insert(slot)
            snapshots[slot] = nil
            return .unknown(message)
        } catch {
            if case CameraError.ptp(.disconnected) = error {
                slotsNeedingVerification.insert(plan.slot)
                handleUnexpectedDisconnect()
                return .unknown("The camera disconnected during the write.")
            }
            return .failed(error.localizedDescription)
        }
    }

    /// Installs a Set slot-by-slot. Not atomic and no automatic rollback: each slot reports its
    /// own outcome, and "Stop" finishes the current slot then stops. Re-entrant calls are ignored.
    func installSet(_ plans: [SlotWritePlan]) async {
        guard !isInstallingSet else { return }
        isInstallingSet = true
        stopRequested = false
        for plan in plans { setOutcomes[plan.slot] = .pending }
        for plan in plans.sorted(by: { $0.slot < $1.slot }) {
            if stopRequested { setOutcomes[plan.slot] = .stopped; continue }
            setOutcomes[plan.slot] = .writing
            let outcome = await execute(plan)
            setOutcomes[plan.slot] = outcome
            if case .unknown = outcome { stopRequested = true }
        }
        isInstallingSet = false
    }

    func requestStop() { stopRequested = true }

    func clearSetOutcomes() {
        guard !isInstallingSet else { return }
        setOutcomes = [:]
    }

    func remainingSlots(of plans: [SlotWritePlan]) -> [SlotWritePlan] {
        plans.filter { setOutcomes[$0.slot] == .stopped || setOutcomes[$0.slot] == .pending }
    }

    // MARK: Diagnostics (redacted; shared only by explicit user action)

    func diagnosticsReport(appVersion: String, osVersion: String) async -> String {
        var lines = [
            "FilmLab diagnostics (redacted)",
            "App \(appVersion) · \(osVersion)",
            "Mode: \(mode) · State: \(state.title)",
            "Camera: \(identity?.model ?? "none") · firmware \(identity?.firmwareVersion ?? "?")",
            "Slots read: \(snapshots.keys.sorted().map(\.label).joined(separator: ","))",
            "Slots needing verification: \(slotsNeedingVerification.sorted().map(\.label).joined(separator: ","))",
            "Last error: \(lastError ?? "none")",
            "— PTP log (operation codes, sizes, response codes; no payloads, no serial numbers) —",
        ]
        if let t = transport { lines += await t.diagnosticsLog() }
        return lines.joined(separator: "\n")
    }
}
