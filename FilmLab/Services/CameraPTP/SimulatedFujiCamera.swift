import Foundation

/// In-memory PTP emulator of a Fujifilm body, used for DEMO MODE and tests.
///
/// It implements only the behaviour described by the community sources (see
/// FujiRecipeCodec provenance) and our own assumptions; it is NOT evidence that real hardware
/// behaves this way. Everything produced through it is labelled "Demo".
actor SimulatedFujiCamera: PTPCommandChannel {
    struct Faults: Sendable {
        /// Respond with this code to the next SetDevicePropValue.
        var failNextWrite: PTPResponseCode?
        /// Accept writes to these properties with OK but silently keep the old value
        /// (ILF: "a camera can return OK without applying a value").
        var silentlyIgnoreWrites: Set<UInt16> = []
        /// Throw `.disconnected` once this many more transactions have completed.
        var disconnectAfterTransactions: Int?
        /// Answer DeviceBusy to everything.
        var busy = false
        /// Pretend the camera is in a USB mode that doesn't expose preset properties.
        var wrongUSBMode = false
    }

    private(set) var slots: [Int: [UInt16: Data]] = [:]
    private(set) var selectedSlot: UInt16 = 1
    private(set) var sessionOpen = false
    private(set) var setCount = 0
    var faults = Faults()
    let model: String
    let firmware: String
    nonisolated var echoesTransactionIDs: Bool { true }

    init(model: String = "X-T30 III", firmware: String = "demo", seed: [CameraSlot: (String, RecipeSettings)] = SimulatedFujiCamera.defaultSeed) {
        self.model = model
        self.firmware = firmware
        for slot in CameraSlot.allCases {
            var props: [UInt16: Data] = [:]
            // Preserve-only properties get opaque placeholder bytes so backups show them.
            props[FujiPresetProperty.imageSize.rawValue] = FujiRecipeCodec.u16(7)
            props[FujiPresetProperty.imageQuality.rawValue] = FujiRecipeCodec.u16(4)
            props[FujiPresetProperty.smoothSkin.rawValue] = FujiRecipeCodec.u16(1)
            props[FujiPresetProperty.lensModOrLongExpNR.rawValue] = FujiRecipeCodec.u16(1)
            props[FujiPresetProperty.colorSpace.rawValue] = FujiRecipeCodec.u16(1)
            let (name, settings) = seed[slot] ?? ("CUSTOM \(slot.rawValue)", RecipeSettings.neutral())
            if let plan = try? FujiRecipeCodec.encode(settings, name: name) {
                for p in plan { props[p.property.rawValue] = Self.stored(p.property, p.bytes) }
            }
            // A real body answers every preset property; fill the ones the seed recipe didn't set.
            for (p, value) in Self.factoryDefaults where props[p.rawValue] == nil {
                props[p.rawValue] = value
            }
            slots[slot.rawValue] = props
        }
    }

    /// Placeholder "factory" values for the emulator only (not Fujifilm data).
    static let factoryDefaults: [FujiPresetProperty: Data] = [
        .dynamicRange: FujiRecipeCodec.u16(100), .dRangePriority: FujiRecipeCodec.u16(0),
        .filmSimulation: FujiRecipeCodec.u16(1), .monoWarmCool: FujiRecipeCodec.i16(0), .monoMagentaGreen: FujiRecipeCodec.i16(0),
        .grain: FujiRecipeCodec.u16(6), .colorChrome: FujiRecipeCodec.u16(1), .colorChromeFXBlue: FujiRecipeCodec.u16(1),
        .whiteBalance: FujiRecipeCodec.u16(2), .wbShiftRed: FujiRecipeCodec.i16(0), .wbShiftBlue: FujiRecipeCodec.i16(0),
        .kelvin: FujiRecipeCodec.u16(6500), .highlight: FujiRecipeCodec.i16(0), .shadow: FujiRecipeCodec.i16(0),
        .color: FujiRecipeCodec.i16(0), .sharpness: FujiRecipeCodec.i16(0), .highISONR: FujiRecipeCodec.u16(0x2000),
        .clarity: FujiRecipeCodec.i16(0),
    ]

    static let defaultSeed: [CameraSlot: (String, RecipeSettings)] = {
        var c1 = RecipeSettings.neutral(.classicChrome)
        c1.highlight = .value(-1); c1.shadow = .value(1); c1.color = .value(-2); c1.grainRoughness = .value(.weak); c1.grainSize = .value(.small)
        var c2 = RecipeSettings.neutral(.acros)
        c2.shadow = .value(2); c2.grainRoughness = .value(.strong); c2.grainSize = .value(.large); c2.monochromaticWarmCool = .value(2)
        var c3 = RecipeSettings.neutral(.nostalgicNeg)
        c3.whiteBalance = .value(.colorTemperature); c3.kelvin = .value(5200); c3.wbShiftRed = .value(2); c3.wbShiftBlue = .value(-3)
        return [.c1: ("DEMO CHROME", c1), .c2: ("DEMO ACROS", c2), .c3: ("DEMO NOSTALGIA", c3)]
    }()

    /// Models the reported X-T30 III read-back quirk: grain OFF (1) reads back as 6.
    private static func stored(_ p: FujiPresetProperty, _ bytes: Data) -> Data {
        if p == .grain, bytes == FujiRecipeCodec.u16(1) { return FujiRecipeCodec.u16(6) }
        return bytes
    }

    func perform(_ command: PTPContainer, outData: Data?, timeout: Duration) async throws -> PTPTransactionResult {
        // Small latency so UI progress states are visible and cancellation can be exercised.
        try await Task.sleep(for: .milliseconds(15))
        if let n = faults.disconnectAfterTransactions {
            if n <= 0 { throw PTPError.disconnected }
            faults.disconnectAfterTransactions = n - 1
        }
        func respond(_ code: PTPResponseCode, _ data: Data = Data()) -> PTPTransactionResult {
            PTPTransactionResult(response: PTPContainer(type: .response, code: code.rawValue, transactionID: command.transactionID), inData: data)
        }
        if faults.busy { return respond(.deviceBusy) }

        switch PTPOperation(rawValue: command.code) {
        case .openSession:
            if sessionOpen { return respond(.sessionAlreadyOpen) }
            sessionOpen = true
            return respond(.ok)
        case .closeSession:
            sessionOpen = false
            return respond(.ok)
        case .getDeviceInfo:
            let props: [UInt16] = faults.wrongUSBMode ? [] : FujiPresetProperty.allCases.map(\.rawValue)
            let info = PTPDeviceInfo(
                standardVersion: 100, vendorExtensionID: 0x0000_000E, vendorExtensionVersion: 100,
                vendorExtensionDesc: "", functionalMode: 0,
                operationsSupported: [0x1001, 0x1002, 0x1003, 0x1014, 0x1015, 0x1016],
                eventsSupported: [], devicePropertiesSupported: props, captureFormats: [], imageFormats: [],
                manufacturer: "FUJIFILM", model: model, deviceVersion: firmware, serialNumber: "DEMO000000")
            return respond(.ok, try info.encoded())
        case .getDevicePropValue:
            guard sessionOpen else { return respond(.sessionNotOpen) }
            guard let code = command.parameters.first.map({ UInt16(truncatingIfNeeded: $0) }) else { return respond(.generalError) }
            if code == FujiPresetProperty.slotSelector.rawValue { return respond(.ok, FujiRecipeCodec.u16(selectedSlot)) }
            if faults.wrongUSBMode { return respond(.devicePropNotSupported) }
            guard let value = slots[Int(selectedSlot)]?[code] else { return respond(.devicePropNotSupported) }
            if code == FujiPresetProperty.dynamicRange.rawValue, drPriorityActive { return respond(.ok, FujiRecipeCodec.u16(0xFFFF)) }
            return respond(.ok, value)
        case .setDevicePropValue:
            guard sessionOpen else { return respond(.sessionNotOpen) }
            guard let code = command.parameters.first.map({ UInt16(truncatingIfNeeded: $0) }), let data = outData else { return respond(.generalError) }
            if let fail = faults.failNextWrite { faults.failNextWrite = nil; return respond(fail) }
            if code == FujiPresetProperty.slotSelector.rawValue {
                var r = PTPReader(data)
                guard let v = try? r.u16(), (1...7).contains(v) else { return respond(.invalidDevicePropValue) }
                selectedSlot = v
                return respond(.ok)
            }
            guard let property = FujiPresetProperty(rawValue: code), property.policy == .readWrite else {
                return respond(.invalidDevicePropValue)
            }
            // ILF: while D RANGE PRIORITY ≠ OFF, writes to DR/highlight/shadow are rejected.
            if drPriorityActive, [.dynamicRange, .highlight, .shadow].contains(property) {
                return respond(.invalidDevicePropValue)
            }
            setCount += 1
            if faults.silentlyIgnoreWrites.contains(code) { return respond(.ok) }
            slots[Int(selectedSlot), default: [:]][code] = Self.stored(property, data)
            return respond(.ok)
        case .getDevicePropDesc, .none:
            return respond(.operationNotSupported)
        }
    }

    private var drPriorityActive: Bool {
        guard let d = slots[Int(selectedSlot)]?[FujiPresetProperty.dRangePriority.rawValue] else { return false }
        return d != FujiRecipeCodec.u16(0)
    }

    func close() async { sessionOpen = false }

    // Test hooks
    func setFaults(_ f: Faults) { faults = f }
    func rawSlot(_ slot: CameraSlot) -> [UInt16: Data] { slots[slot.rawValue] ?? [:] }
}
