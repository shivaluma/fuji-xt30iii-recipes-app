import Testing
import Foundation
import CoreGraphics
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("Camera controller safety flows (demo camera)")
@MainActor
struct CameraFlowTests {
    func makeController(experimentalWrites: Bool = false) -> (CameraController, AppPaths) {
        let paths = AppPaths.temporary()
        let defaults = UserDefaults(suiteName: "filmlab.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.experimentalSlotWrites = experimentalWrites
        return (CameraController(settings: settings, backupStore: CameraBackupStore(directory: paths.backups)), paths)
    }

    @Test("Demo connection is clearly demo and writable only via explicit flow")
    func demoConnect() async {
        let (c, _) = makeController()
        await c.connectDemo()
        #expect(c.isDemo)
        #expect(c.identity?.isDemo == true)
        #expect(c.state.canWrite)
        #expect(c.snapshots.isEmpty) // connecting doesn't read or write anything implicitly
        #expect(await c.demoCamera?.setCount == 0)
    }

    @Test("prepareWrite backs up all slots first and performs no writes")
    func backupFirst() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        await c.demoCamera?.setFaults(.init())
        let plan = try await c.prepareWrite(recipe: StarterRecipes.all[0], slot: .c3)
        #expect(c.backups.count == 1)
        #expect(c.backups[0].snapshots.count == 7)
        #expect(plan.backupID == c.backups[0].id)
        #expect(plan.before?.name == "DEMO NOSTALGIA")
        #expect(plan.diff.contains { $0.key == .filmSimulation && $0.kind == .changed })
        #expect(await c.demoCamera?.setCount == 0)
    }

    @Test("Executing a confirmed plan writes, verifies, and updates the snapshot")
    func execute() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        let plan = try await c.prepareWrite(recipe: StarterRecipes.all[5], slot: .c7)
        let outcome = await c.execute(plan)
        #expect(outcome == .verified)
        #expect(c.snapshots[.c7]?.settings?.filmSimulation == StarterRecipes.all[5].filmSimulation)
        #expect(c.snapshots[.c7]?.name == FujiRecipeCodec.suggestedSlotName(for: StarterRecipes.all[5].name))
    }

    @Test("A plan without a backup is refused")
    func noBackup() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        var plan = try await c.prepareWrite(recipe: StarterRecipes.all[0], slot: .c1)
        plan.backupID = nil
        let outcome = await c.execute(plan)
        if case .failed = outcome {} else { Issue.record("expected failure, got \(outcome)") }
    }

    @Test("A plan reviewed on a previous connection is refused after reconnecting")
    func stalePlanAfterReconnect() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        let plan = try await c.prepareWrite(recipe: StarterRecipes.all[0], slot: .c2)
        await c.disconnect()
        #expect(c.snapshots.isEmpty && c.sessionBackupID == nil)
        await c.connectDemo()
        let outcome = await c.execute(plan)
        if case .failed = outcome {} else { Issue.record("expected refusal, got \(outcome)") }
        #expect(await c.demoCamera?.setCount == 0)
    }

    @Test("A failed read is not saved as a backup")
    func noStaleBackup() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        await c.readAllSlots()
        var f = SimulatedFujiCamera.Faults(); f.busy = true
        await c.demoCamera?.setFaults(f)
        #expect(await c.backupAll(reason: "t") == nil)
        #expect(c.backups.isEmpty)
    }

    @Test("Blocking validation issues prevent writes")
    func blocking() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        let plan = try await c.prepareWrite(recipe: StarterRecipes.all[0], slot: .c1, slotName: "Bad ☕️ name")
        #expect(plan.hasBlockingIssues)
        let before = await c.demoCamera?.setCount
        _ = await c.execute(plan)
        #expect(await c.demoCamera?.setCount == before)
    }

    @Test("Set install: partial failure is reported per slot, stop finishes cleanly")
    func setInstallPartial() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        var plans: [SlotWritePlan] = []
        for (i, r) in StarterRecipes.all.prefix(3).enumerated() {
            plans.append(try await c.prepareWrite(recipe: r, slot: CameraSlot(index: i)!))
        }
        var f = SimulatedFujiCamera.Faults(); f.failNextWrite = .invalidDevicePropValue
        await c.demoCamera?.setFaults(f)
        await c.installSet(plans)
        #expect(c.setOutcomes[.c1] != .verified) // first property write rejected
        #expect(c.setOutcomes[.c2] == .verified)
        #expect(c.setOutcomes[.c3] == .verified)
        #expect(!c.isInstallingSet)
    }

    @Test("Disconnect during a Set marks the slot unknown and stops the rest")
    func setInstallDisconnect() async throws {
        let (c, _) = makeController()
        await c.connectDemo()
        var plans: [SlotWritePlan] = []
        for (i, r) in StarterRecipes.all.prefix(3).enumerated() {
            plans.append(try await c.prepareWrite(recipe: r, slot: CameraSlot(index: i)!))
        }
        var f = SimulatedFujiCamera.Faults(); f.disconnectAfterTransactions = 5
        await c.demoCamera?.setFaults(f)
        await c.installSet(plans)
        if case .unknown = c.setOutcomes[.c1] {} else { Issue.record("expected unknown, got \(String(describing: c.setOutcomes[.c1]))") }
        #expect(c.setOutcomes[.c2] == .stopped)
        #expect(c.setOutcomes[.c3] == .stopped)
        #expect(c.slotsNeedingVerification.contains(.c1))
        #expect(c.remainingSlots(of: plans).map(\.slot) == [.c2, .c3])
    }

    @Test("Diagnostics are redacted")
    func diagnostics() async {
        let (c, _) = makeController()
        await c.connectDemo()
        await c.readAllSlots()
        let report = await c.diagnosticsReport(appVersion: "t", osVersion: "t")
        #expect(report.contains("op 0x1015"))
        #expect(!report.contains("DEMO000000"))   // serial
        #expect(!report.contains("DEMO CHROME"))  // slot payload content
    }

    @Test("Studio rendering never touches the camera")
    func studioNeverWrites() async throws {
        let (c, paths) = makeController()
        await c.connectDemo()
        let library = LibraryStore(paths: paths)
        library.ensureDemoAssets()
        let renderer = OfflinePreviewRenderer(diskCacheDirectory: nil)
        let studio = StudioModel(renderer: renderer, library: library, cameraRenderService: DemoCameraRenderService(renderer: renderer, simulatedLatency: .milliseconds(1)))
        await studio.select(try #require(library.assets.first))
        for r in StarterRecipes.all.prefix(4) { studio.load(r); await studio.waitForRender() }
        studio.renderWithCamera()
        try await Task.sleep(for: .milliseconds(300))
        #expect(studio.cameraPreview?.fidelity == .demoSimulatedCamera) // never authentic in demo
        #expect(await c.demoCamera?.setCount == 0)
        #expect(c.snapshots.isEmpty)
    }

    @Test("Real-hardware camera render stays disabled and never claims authenticity")
    func unvalidatedRender() async {
        let svc = UnvalidatedCameraRenderService(isCameraConnected: { true })
        let a = await svc.availability(for: nil)
        #expect(!a.isUsable)
        if case .notValidated = a {} else { Issue.record("expected notValidated") }
    }

    @Test("Authentic JPEG validator rejects non-JPEG bytes")
    func jpegValidator() throws {
        #expect(throws: CameraRenderError.invalidJPEG) { try AuthenticJPEGValidator.validate(Data([0xFF, 0xD8, 0x00, 0xFF, 0xD9])) }
        #expect(throws: CameraRenderError.invalidJPEG) { try AuthenticJPEGValidator.validate(Data(repeating: 0, count: 100)) }
        let jpeg = try #require(DemoImageFactory.jpegData(for: DemoImageFactory.scenes[1], size: CGSize(width: 64, height: 48)))
        #expect(try AuthenticJPEGValidator.validate(jpeg).width == 64)
    }
}
