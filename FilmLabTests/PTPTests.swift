import Testing
import Foundation
import CoreGraphics
#if !FILMLAB_CLI
@testable import FilmLab
#endif

@Suite("PTP containers & parsing")
struct PTPCoreTests {

    @Test("Command container encodes little-endian with correct length")
    func encodeCommand() throws {
        let c = PTPContainer.command(0x1015, transactionID: 0x01020304, parameters: [0xD18C])
        let bytes = [UInt8](try c.encoded())
        #expect(bytes == [0x10, 0, 0, 0, 0x01, 0x00, 0x15, 0x10, 0x04, 0x03, 0x02, 0x01, 0x8C, 0xD1, 0, 0])
        #expect(try PTPContainer.decode(Data(bytes)) == c)
    }

    @Test("Data container roundtrip")
    func dataRoundtrip() throws {
        let c = PTPContainer(type: .data, code: 0x1016, transactionID: 9, payload: Data([1, 2, 3]))
        #expect(try PTPContainer.decode(try c.encoded()) == c)
    }

    @Test("Malformed containers are rejected, not crashed on")
    func malformed() {
        #expect(throws: PTPError.self) { try PTPContainer.decode(Data([0x0C, 0, 0])) }                               // short header
        #expect(throws: PTPError.invalidLength(4)) { try PTPContainer.decode(Data([4, 0, 0, 0, 1, 0, 1, 0x10, 0, 0, 0, 0])) }
        #expect(throws: PTPError.invalidContainerType(9)) { try PTPContainer.decode(Data([12, 0, 0, 0, 9, 0, 1, 0x10, 0, 0, 0, 0])) }
        #expect(throws: PTPError.truncated(needed: 64, available: 12)) { try PTPContainer.decode(Data([64, 0, 0, 0, 2, 0, 1, 0x10, 0, 0, 0, 0])) }
        #expect(throws: PTPError.invalidLength(14)) { try PTPContainer.decode(Data([14, 0, 0, 0, 3, 0, 1, 0x20, 0, 0, 0, 0, 0, 0])) } // params not multiple of 4
        #expect(throws: PTPError.tooManyParameters(6)) {
            try PTPContainer.decode(Data([36, 0, 0, 0, 3, 0, 1, 0x20, 0, 0, 0, 0] + Array(repeating: 0, count: 24)))
        }
        #expect(throws: PTPError.self) { try PTPContainer.decode(Data([0xFF, 0xFF, 0xFF, 0x7F, 2, 0, 1, 0x10, 0, 0, 0, 0])) } // oversized
        #expect(throws: PTPError.tooManyParameters(6)) { try PTPContainer.command(1, transactionID: 1, parameters: [1, 2, 3, 4, 5, 6]).encoded() }
    }

    @Test("Random bytes never crash the decoders (fuzz-like)")
    func fuzz() {
        var rng = SystemRandomNumberGenerator()
        for i in 0..<3000 {
            let n = Int.random(in: 0...64, using: &rng)
            var bytes = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
            if i % 3 == 0, bytes.count >= 4 { bytes[0] = UInt8(n); bytes[1] = 0; bytes[2] = 0; bytes[3] = 0 } // plausible lengths
            _ = try? PTPContainer.decode(Data(bytes))
            _ = try? PTPDeviceInfo.decode(Data(bytes))
            _ = FujiRecipeCodec.decode([FujiPresetProperty.filmSimulation.rawValue: Data(bytes.prefix(2)),
                                        FujiPresetProperty.slotName.rawValue: Data(bytes)])
        }
    }

    @Test("PTP strings: documented example and invalid input")
    func strings() throws {
        var w = PTPWriter()
        try w.string("C1")
        #expect([UInt8](w.data) == [0x03, 0x43, 0x00, 0x31, 0x00, 0x00, 0x00]) // ILF protocol.md example
        var r = PTPReader(w.data)
        #expect(try r.string() == "C1")
        var bad = PTPReader(Data([0x02, 0x41, 0x00, 0x42, 0x00])) // no NUL terminator
        #expect(throws: PTPError.invalidString) { try bad.string() }
        var short = PTPReader(Data([0x05, 0x41]))
        #expect(throws: PTPError.self) { try short.string() }
        var empty = PTPWriter(); try empty.string("")
        #expect(empty.data == Data([0]))
    }

    @Test("DeviceInfo roundtrip and bounded arrays")
    func deviceInfo() throws {
        let info = PTPDeviceInfo(standardVersion: 100, vendorExtensionID: 14, vendorExtensionVersion: 100, vendorExtensionDesc: "",
                                 functionalMode: 0, operationsSupported: [0x1001, 0x1015], eventsSupported: [],
                                 devicePropertiesSupported: [0xD18C], captureFormats: [], imageFormats: [0x3801],
                                 manufacturer: "FUJIFILM", model: "X-T30 III", deviceVersion: "1.10", serialNumber: "123")
        #expect(try PTPDeviceInfo.decode(try info.encoded()) == info)
        var w = PTPWriter(); w.u16(100); w.u32(0); w.u16(0); w.u8(0); w.u16(0); w.u32(1_000_000)
        #expect(throws: PTPError.payloadTooLarge(1_000_000)) { try PTPDeviceInfo.decode(w.data) }
    }
}

@Suite("Fujifilm recipe codec (third-party-reported encodings)")
struct FujiCodecTests {
    func plan(_ s: RecipeSettings, name: String? = "TEST") throws -> [FujiPresetProperty: Data] {
        Dictionary(uniqueKeysWithValues: try FujiRecipeCodec.encode(s, name: name).map { ($0.property, $0.bytes) })
    }

    @Test("Tone values are encoded as value × 10 (−1.5 → F1 FF)")
    func tenths() throws {
        var s = RecipeSettings.neutral(.provia)
        s.highlight = .value(-1.5)
        s.shadow = .value(4)
        let p = try plan(s)
        #expect(p[.highlight] == Data([0xF1, 0xFF]))
        #expect(p[.shadow] == Data([40, 0]))
    }

    @Test("High ISO NR uses the non-linear table")
    func nr() throws {
        for (v, code) in [(-4, 0x8000), (0, 0x2000), (2, 0x0000), (4, 0x5000)] {
            var s = RecipeSettings.neutral(); s.highISONR = .value(v)
            #expect(try plan(s)[.highISONR] == FujiRecipeCodec.u16(UInt16(code)))
        }
    }

    @Test("Grain, WB, film simulation codes")
    func codes() throws {
        var s = RecipeSettings.neutral(.realaAce)
        s.grainRoughness = .value(.strong); s.grainSize = .value(.large)
        s.whiteBalance = .value(.colorTemperature); s.kelvin = .value(5200)
        let p = try plan(s)
        #expect(p[.filmSimulation] == FujiRecipeCodec.u16(20))
        #expect(p[.grain] == FujiRecipeCodec.u16(5))
        #expect(p[.whiteBalance] == FujiRecipeCodec.u16(0x8007))
        #expect(p[.kelvin] == FujiRecipeCodec.u16(5200))
        #expect(FujiRecipeCodec.decodeGrain(6)! == (.off, nil))
        #expect(FujiRecipeCodec.decodeGrain(99) == nil)
    }

    @Test("Write order: film sim first, Kelvin right after WB, name last; unset/n-a omitted")
    func order() throws {
        var s = RecipeSettings(filmSimulation: .acros)
        s.whiteBalance = .value(.colorTemperature); s.kelvin = .value(6000)
        s.color = .value(3) // n/a on ACROS → never written
        s.shadow = .value(1)
        let items = try FujiRecipeCodec.encode(s, name: "BW").map(\.property)
        #expect(items.first == .filmSimulation)
        #expect(items.last == .slotName)
        let wb = try #require(items.firstIndex(of: .whiteBalance))
        #expect(items[wb + 1] == .kelvin)
        #expect(!items.contains(.color))
        #expect(!items.contains(.highlight)) // unset
        #expect(!items.contains { $0.policy == .readOnlyPreserve })
    }

    @Test("With D RANGE PRIORITY on, DR/highlight/shadow are not written")
    func drp() throws {
        var s = RecipeSettings.neutral(); s.dRangePriority = .value(.weak); s.highlight = .value(2)
        let p = try plan(s)
        #expect(p[.dRangePriority] == FujiRecipeCodec.u16(1))
        #expect(p[.dynamicRange] == nil && p[.highlight] == nil && p[.shadow] == nil)
    }

    @Test("Encode → decode roundtrip for every fixture recipe")
    func roundtrip() throws {
        for r in TestRecipes.all {
            let p = try FujiRecipeCodec.encode(r.settings, name: "X")
            let decoded = FujiRecipeCodec.decode(Dictionary(uniqueKeysWithValues: p.map { ($0.property.rawValue, $0.bytes) }))
            let d = try #require(decoded.settings)
            #expect(decoded.name == "X")
            #expect(d.filmSimulation == r.settings.filmSimulation, "\(r.name)")
            #expect(d.highlight == r.settings.highlight, "\(r.name)")
            #expect(d.shadow == r.settings.shadow, "\(r.name)")
            #expect(d.color == r.settings.color, "\(r.name)")
            #expect(d.grainRoughness == r.settings.grainRoughness, "\(r.name)")
            #expect(d.whiteBalance == r.settings.whiteBalance, "\(r.name)")
            #expect(d.kelvin == r.settings.kelvin, "\(r.name)")
            #expect(d.highISONR == r.settings.highISONR, "\(r.name)")
            #expect(d.monochromaticWarmCool == r.settings.monochromaticWarmCool, "\(r.name)")
        }
    }

    @Test("Decoding flags unknown values and honours the unset sentinel")
    func decodeUnknown() {
        let values: [UInt16: Data] = [
            FujiPresetProperty.filmSimulation.rawValue: FujiRecipeCodec.u16(1),
            FujiPresetProperty.colorChrome.rawValue: FujiRecipeCodec.u16(77),   // unknown code
            FujiPresetProperty.highlight.rawValue: FujiRecipeCodec.i16(fujiUnsetSentinel),
            FujiPresetProperty.imageSize.rawValue: Data([7, 0]),              // preserve-only
        ]
        let r = FujiRecipeCodec.decode(values)
        #expect(r.settings?.colorChrome == .unset)
        #expect(r.settings?.highlight == .unset)
        #expect(r.unknown.contains { $0.code == FujiPresetProperty.colorChrome.rawValue })
        #expect(r.unknown.contains { $0.code == FujiPresetProperty.imageSize.rawValue })
        #expect(FujiRecipeCodec.decode([FujiPresetProperty.filmSimulation.rawValue: FujiRecipeCodec.u16(200)]).settings == nil)
    }

    @Test("Slot names are validated and sanitised")
    func names() throws {
        #expect(try FujiRecipeCodec.validatedSlotName("  Golden Hour ") == "Golden Hour")
        #expect(throws: FujiRecipeCodec.CodecError.self) { try FujiRecipeCodec.validatedSlotName("") }
        #expect(throws: FujiRecipeCodec.CodecError.self) { try FujiRecipeCodec.validatedSlotName(String(repeating: "A", count: 26)) }
        #expect(throws: FujiRecipeCodec.CodecError.self) { try FujiRecipeCodec.validatedSlotName("Café ☕️") }
        #expect(FujiRecipeCodec.suggestedSlotName(for: "Café “Noir” ☕️ — très long name here!") == "Cafe Noir tres long name")
        #expect(FujiRecipeCodec.suggestedSlotName(for: "☕️") == "FilmLab")
    }
}

// MARK: - Session

/// Channel used to test session validation and serialization.
actor ScriptedChannel: PTPCommandChannel {
    var responseCode: UInt16 = 0x2001
    var echoTID = true
    var wrongTID = false
    var delay: Duration = .zero
    var hang = false
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    nonisolated var echoesTransactionIDs: Bool { true }

    func configure(code: UInt16 = 0x2001, wrongTID: Bool = false, delay: Duration = .zero, hang: Bool = false) {
        responseCode = code; self.wrongTID = wrongTID; self.delay = delay; self.hang = hang
    }

    func perform(_ command: PTPContainer, outData: Data?, timeout: Duration) async throws -> PTPTransactionResult {
        inFlight += 1; maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        if hang {
            return try await withPTPTimeout(timeout, operation: command.code) {
                try await Task.sleep(for: .seconds(60))
                throw PTPError.cancelled
            }
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        let tid = wrongTID ? command.transactionID + 7 : command.transactionID
        return PTPTransactionResult(response: PTPContainer(type: .response, code: responseCode, transactionID: tid), inData: Data([1, 0]))
    }

    func close() async {}
}

@Suite("PTP session")
struct PTPSessionTests {
    @Test("Non-OK responses throw with the response code")
    func nonOK() async {
        let ch = ScriptedChannel()
        await ch.configure(code: 0x201C)
        let s = PTPSession(channel: ch)
        await #expect(throws: PTPError.response(.invalidDevicePropValue, operation: 0x1016)) {
            try await s.setPropertyValue(0xD190, Data([0, 0]))
        }
    }

    @Test("Transaction ID mismatch is a protocol error")
    func tidMismatch() async {
        let ch = ScriptedChannel()
        await ch.configure(wrongTID: true)
        let s = PTPSession(channel: ch)
        await #expect(throws: PTPError.self) { _ = try await s.getPropertyValue(0xD18C) }
    }

    @Test("Timeouts surface as PTPError.timeout")
    func timeout() async {
        let ch = ScriptedChannel()
        await ch.configure(hang: true)
        let s = PTPSession(channel: ch)
        await #expect(throws: PTPError.timeout(operation: 0x1015)) {
            _ = try await s.transact(0x1015, parameters: [0xD18C], timeout: .milliseconds(50))
        }
    }

    @Test("Only one transaction is ever in flight")
    func serialization() async throws {
        let ch = ScriptedChannel()
        await ch.configure(delay: .milliseconds(5))
        let s = PTPSession(channel: ch)
        try await withThrowingTaskGroup(of: Void.self) { g in
            for _ in 0..<20 { g.addTask { _ = try await s.getPropertyValue(0xD18C) } }
            try await g.waitForAll()
        }
        #expect(await ch.maxInFlight == 1)
        #expect(await s.log.count == 20)
        #expect(await s.log.allSatisfy { !$0.line.contains("01 00") }) // logs never include payload bytes
    }
}

// MARK: - Transport over the simulated camera

@Suite("Fuji transport (simulated camera)")
struct TransportTests {
    func make(writes: Bool = true, faults: SimulatedFujiCamera.Faults = .init()) async -> (SimulatedFujiCamera, FujiPTPCameraTransport) {
        let cam = SimulatedFujiCamera()
        await cam.setFaults(faults)
        let t = FujiPTPCameraTransport(channel: cam, kind: .demo, opensPTPSession: true, writesEnabled: { writes })
        await t.setFastSlotSelect()
        return (cam, t)
    }

    @Test("Connect reports a demo X-T30 III with a hashed serial")
    func connect() async throws {
        let (_, t) = await make()
        let id = try await t.connect()
        #expect(id.model == "X-T30 III")
        #expect(id.isDemo)
        #expect(id.serialHash != nil && id.serialHash != "DEMO000000")
    }

    @Test("Wrong USB mode is diagnosed")
    func wrongMode() async {
        var f = SimulatedFujiCamera.Faults(); f.wrongUSBMode = true
        let (_, t) = await make(faults: f)
        await #expect(throws: CameraError.self) { _ = try await t.connect() }
        do { _ = try await t.connect() } catch let e as CameraError {
            if case .wrongMode = e {} else { Issue.record("expected wrongMode, got \(e)") }
        } catch { Issue.record("\(error)") }
    }

    @Test("Reads all seven slots and restores the selected slot")
    func readAll() async throws {
        let (cam, t) = await make()
        _ = try await t.connect()
        let snaps = try await t.readSlots(CameraSlot.allCases)
        #expect(snaps.count == 7)
        #expect(snaps[0].name == "DEMO CHROME")
        #expect(snaps[0].settings?.filmSimulation == .classicChrome)
        #expect(snaps[1].settings?.filmSimulation == .acros)
        #expect(snaps[2].settings?.kelvin == .value(5200))
        #expect(snaps.allSatisfy { $0.completeness == .complete })
        #expect(snaps[0].rawValues.contains { $0.code == FujiPresetProperty.imageSize.rawValue }) // preserved
        #expect(await cam.selectedSlot == 1)
        #expect(await cam.setCount == 0) // reading never writes preset properties
    }

    @Test("Reading is stable: two reads give identical snapshots")
    func stableReads() async throws {
        let (_, t) = await make()
        _ = try await t.connect()
        let a = try await t.readSlots(CameraSlot.allCases)
        let b = try await t.readSlots(CameraSlot.allCases)
        #expect(a.map(\.rawValues) == b.map(\.rawValues))
    }

    @Test("Write + read-back verification succeeds and leaves other slots untouched")
    func writeVerified() async throws {
        let (cam, t) = await make()
        _ = try await t.connect()
        let before = await cam.rawSlot(.c1)
        let recipe = TestRecipes.all[3] // ACROS+R
        let report = try await t.writeSlot(.c5, settings: recipe.settings, name: "PAPER MOON")
        #expect(report.outcome == .verified, "\(report.mismatches.map(\.description))")
        #expect(report.after.name == "PAPER MOON")
        #expect(report.after.settings?.filmSimulation == .acrosR)
        #expect(await cam.rawSlot(.c1) == before)
    }

    @Test("Writes are refused when disabled")
    func writesDisabled() async throws {
        let (cam, t) = await make(writes: false)
        _ = try await t.connect()
        await #expect(throws: CameraError.writesDisabled) {
            _ = try await t.writeSlot(.c1, settings: .neutral(), name: "X")
        }
        #expect(await cam.setCount == 0)
    }

    @Test("Silently ignored writes are reported as exact mismatches")
    func mismatch() async throws {
        var f = SimulatedFujiCamera.Faults(); f.silentlyIgnoreWrites = [FujiPresetProperty.shadow.rawValue]
        let (_, t) = await make(faults: f)
        _ = try await t.connect()
        var s = RecipeSettings.neutral(.provia); s.shadow = .value(3)
        let report = try await t.writeSlot(.c4, settings: s, name: "MM")
        #expect(report.outcome == .mismatched)
        #expect(report.mismatches.map(\.property) == [.shadow])
        #expect(report.mismatches[0].expected == Data([30, 0]))
    }

    @Test("Disconnect mid-write yields outcomeUnknown, never success")
    func disconnectMidWrite() async throws {
        let (cam, t) = await make()
        _ = try await t.connect()
        var f = SimulatedFujiCamera.Faults(); f.disconnectAfterTransactions = 4
        await cam.setFaults(f)
        do {
            _ = try await t.writeSlot(.c2, settings: TestRecipes.all[1].settings, name: "X")
            Issue.record("expected failure")
        } catch CameraError.outcomeUnknown(let slot, _) {
            #expect(slot == .c2)
        }
    }

    @Test("A failure before any property is written is a clean failure")
    func failBeforeWrite() async throws {
        let (cam, t) = await make()
        _ = try await t.connect()
        var f = SimulatedFujiCamera.Faults(); f.busy = true
        await cam.setFaults(f)
        await #expect(throws: CameraError.busy) { _ = try await t.writeSlot(.c1, settings: .neutral(), name: "X") }
        #expect(await cam.setCount == 0)
    }

    @Test("Grain OFF read-back quirk is treated as equivalent")
    func grainQuirk() async throws {
        let (_, t) = await make()
        _ = try await t.connect()
        var s = RecipeSettings.neutral(.provia); s.grainRoughness = .value(.off)
        let report = try await t.writeSlot(.c6, settings: s, name: "G")
        #expect(report.outcome == .verified)
        #expect(report.after.settings?.grainRoughness == .value(.off))
    }
}

extension FujiPTPCameraTransport {
    func setFastSlotSelect() { slotSelectDelay = .milliseconds(1) }
}
