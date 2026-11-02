import Foundation

/// Fujifilm custom-preset device property codes.
///
/// ⚠️ PROVENANCE: every code and encoding here is REPORTED BY THIRD PARTIES (community reverse
/// engineering), not documented by Fujifilm, and NOT yet verified on our own X-T30 III:
///  - ILFforever/fujifilm-ptp-recipes docs/properties.md + docs/protocol.md (CC BY 4.0 docs)
///  - beudbeud/reshipi RecipePreset.kt / FujiCamera.kt (MIT), which reports X-T30 III validation
/// Where the two sources disagree, the property is marked `.readOnlyPreserve` and is never written.
/// See docs/ptp-validation.md before changing anything here.
enum FujiPresetProperty: UInt16, CaseIterable, Sendable {
    case slotSelector = 0xD18C
    case slotName = 0xD18D
    case imageSize = 0xD18E          // disputed meaning/encoding → never written
    case imageQuality = 0xD18F       // disputed → never written
    case dynamicRange = 0xD190
    case dRangePriority = 0xD191
    case filmSimulation = 0xD192
    case monoWarmCool = 0xD193
    case monoMagentaGreen = 0xD194
    case grain = 0xD195
    case colorChrome = 0xD196
    case colorChromeFXBlue = 0xD197
    case smoothSkin = 0xD198         // not present on X-T30 III per manual → never written
    case whiteBalance = 0xD199
    case wbShiftRed = 0xD19A
    case wbShiftBlue = 0xD19B
    case kelvin = 0xD19C
    case highlight = 0xD19D
    case shadow = 0xD19E
    case color = 0xD19F
    case sharpness = 0xD1A0
    case highISONR = 0xD1A1
    case clarity = 0xD1A2
    case lensModOrLongExpNR = 0xD1A3 // sources disagree → never written
    case colorSpace = 0xD1A4         // ILF: never write

    enum Policy: Sendable { case selector, readWrite, readOnlyPreserve }

    var policy: Policy {
        switch self {
        case .slotSelector: .selector
        case .imageSize, .imageQuality, .smoothSkin, .lensModOrLongExpNR, .colorSpace: .readOnlyPreserve
        default: .readWrite
        }
    }

    /// Properties read for a slot snapshot (ILF read flow: name + 0xD18E…0xD1A4).
    static let slotReadOrder: [FujiPresetProperty] = allCases.filter { $0 != .slotSelector }

    var hex: String { String(format: "0x%04X", rawValue) }
}

/// i16 sentinel both community sources describe as "default / unset".
let fujiUnsetSentinel: Int16 = -32768

/// Converts between `RecipeSettings` and raw property bytes. Pure and fully unit-tested.
enum FujiRecipeCodec {

    // MARK: Value tables (third-party reported)

    static let filmSimulationCodes: [FilmSimulation: UInt16] = [
        .provia: 1, .velvia: 2, .astia: 3, .proNegHi: 4, .proNegStd: 5,
        .monochrome: 6, .monochromeYe: 7, .monochromeR: 8, .monochromeG: 9, .sepia: 10,
        .classicChrome: 11, .acros: 12, .acrosYe: 13, .acrosR: 14, .acrosG: 15,
        .eterna: 16, .classicNeg: 17, .eternaBleachBypass: 18, .nostalgicNeg: 19, .realaAce: 20,
    ]

    static let whiteBalanceCodes: [WhiteBalanceMode: UInt16] = [
        .auto: 2, .daylight: 4, .incandescent: 6, .underwater: 8,
        .fluorescent1: 0x8001, .fluorescent2: 0x8002, .fluorescent3: 0x8003,
        .shade: 0x8006, .colorTemperature: 0x8007,
        .custom1: 0x8008, .custom2: 0x8009, .custom3: 0x800A,
        .autoWhitePriority: 0x8020, .autoAmbiencePriority: 0x8021,
    ]

    static let effectCodes: [EffectLevel: UInt16] = [.off: 1, .weak: 2, .strong: 3]

    static let dynamicRangeCodes: [DynamicRangeSetting: UInt16] = [.auto: 0, .dr100: 100, .dr200: 200, .dr400: 400]

    static let dRangePriorityCodes: [DRangePriority: UInt16] = [.off: 0, .weak: 1, .strong: 2, .auto: 0x8000]

    /// Non-linear High ISO NR table (both sources agree).
    static let highISONRCodes: [Int: UInt16] = [
        -4: 0x8000, -3: 0x7000, -2: 0x4000, -1: 0x3000, 0: 0x2000, 1: 0x1000, 2: 0x0000, 3: 0x6000, 4: 0x5000,
    ]

    static func grainCode(_ roughness: GrainRoughness, _ size: GrainSize?) -> UInt16 {
        switch (roughness, size ?? .small) {
        case (.off, _): 1
        case (.weak, .small): 2
        case (.strong, .small): 3
        case (.weak, .large): 4
        case (.strong, .large): 5
        }
    }

    static func decodeGrain(_ code: UInt16) -> (GrainRoughness, GrainSize?)? {
        switch code {
        case 1: (.off, nil)
        case 2: (.weak, .small)
        case 3: (.strong, .small)
        case 4: (.weak, .large)
        case 5: (.strong, .large)
        // Read-back-only codes reported for "off" (reshipi: X-T30 III returns 6/7 after writing 1).
        case 6, 7: (.off, nil)
        default: nil
        }
    }

    // MARK: Encoding

    struct EncodedProperty: Equatable, Sendable {
        var property: FujiPresetProperty
        var bytes: Data
    }

    static func u16(_ v: UInt16) -> Data { var w = PTPWriter(); w.u16(v); return w.data }
    static func i16(_ v: Int16) -> Data { var w = PTPWriter(); w.i16(v); return w.data }
    static func tenths(_ v: Double) -> Data { i16(Int16((v * 10).rounded())) }

    /// Encodes a normalized recipe into an ordered write plan.
    ///
    /// Order follows ILF's documented write flow: FilmSim → DR Priority → DR (only if priority
    /// is OFF) → effects → WB, Kelvin, shifts → tone/colour/detail → name LAST.
    /// (reshipi writes the name first; the disagreement is recorded in docs/ptp-validation.md.)
    /// `.unset` and `.notApplicable` fields are omitted, never defaulted.
    static func encode(_ input: RecipeSettings, name: String?) throws -> [EncodedProperty] {
        let s = input.normalized()
        var out: [EncodedProperty] = []
        func add(_ p: FujiPresetProperty, _ d: Data) { out.append(.init(property: p, bytes: d)) }

        guard let sim = filmSimulationCodes[s.filmSimulation] else { throw CodecError.unsupported(.filmSimulation) }
        add(.filmSimulation, u16(sim))
        if let v = s.dRangePriority.concreteValue, let c = dRangePriorityCodes[v] { add(.dRangePriority, u16(c)) }
        if s.isToneAndDRManual, let v = s.dynamicRange.concreteValue, let c = dynamicRangeCodes[v] { add(.dynamicRange, u16(c)) }

        if let r = s.grainRoughness.concreteValue { add(.grain, u16(grainCode(r, s.grainSize.concreteValue))) }
        if let v = s.colorChrome.concreteValue, let c = effectCodes[v] { add(.colorChrome, u16(c)) }
        if let v = s.colorChromeFXBlue.concreteValue, let c = effectCodes[v] { add(.colorChromeFXBlue, u16(c)) }

        if let wb = s.whiteBalance.concreteValue, let c = whiteBalanceCodes[wb] {
            add(.whiteBalance, u16(c))
            // reshipi: Kelvin "must directly follow WB mode".
            if wb == .colorTemperature, let k = s.kelvin.concreteValue {
                guard (2500...10000).contains(k) else { throw CodecError.outOfRange(.kelvin) }
                add(.kelvin, u16(UInt16(k)))
            }
        }
        if let v = s.wbShiftRed.concreteValue { add(.wbShiftRed, i16(Int16(clamping: v))) }
        if let v = s.wbShiftBlue.concreteValue { add(.wbShiftBlue, i16(Int16(clamping: v))) }

        if s.isToneAndDRManual {
            if let v = s.highlight.concreteValue { add(.highlight, tenths(v)) }
            if let v = s.shadow.concreteValue { add(.shadow, tenths(v)) }
        }
        if let v = s.color.concreteValue { add(.color, tenths(Double(v))) }
        if let v = s.sharpness.concreteValue { add(.sharpness, tenths(Double(v))) }
        if let v = s.highISONR.concreteValue {
            guard let c = highISONRCodes[v] else { throw CodecError.outOfRange(.highISONR) }
            add(.highISONR, u16(c))
        }
        if let v = s.clarity.concreteValue { add(.clarity, tenths(Double(v))) }
        if let v = s.monochromaticWarmCool.concreteValue { add(.monoWarmCool, tenths(Double(v))) }
        if let v = s.monochromaticMagentaGreen.concreteValue { add(.monoMagentaGreen, tenths(Double(v))) }

        if let name {
            let clean = try validatedSlotName(name)
            var w = PTPWriter(); try w.string(clean)
            add(.slotName, w.data)
        }
        return out
    }

    enum CodecError: Error, Equatable, LocalizedError {
        case unsupported(RecipePropertyKey)
        case outOfRange(RecipePropertyKey)
        case invalidName(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let k): "\(k.displayName) can't be encoded for this camera."
            case .outOfRange(let k): "\(k.displayName) is out of the camera's range."
            case .invalidName(let why): "Slot name: \(why)"
            }
        }
    }

    /// ILF reports a 25-character limit and an ASCII letters/digits/space/limited-punctuation
    /// character set. Not verified against the X-T30 III manual (which states no limit).
    static let slotNameMaxLength = 25
    static let slotNameAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_.,&'()+!/")

    static func validatedSlotName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw CodecError.invalidName("must not be empty") }
        guard trimmed.count <= slotNameMaxLength else { throw CodecError.invalidName("max \(slotNameMaxLength) characters") }
        guard trimmed.unicodeScalars.allSatisfy(slotNameAllowed.contains) else {
            throw CodecError.invalidName("use letters, digits, spaces and - _ . , & ' ( ) + ! /")
        }
        return trimmed
    }

    /// Best-effort conversion of an arbitrary recipe name into a camera-safe slot name.
    static func suggestedSlotName(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
        let filtered = String(folded.unicodeScalars.filter(slotNameAllowed.contains).map(Character.init))
        let collapsed = filtered.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let clipped = String(collapsed.prefix(slotNameMaxLength)).trimmingCharacters(in: .whitespaces)
        return clipped.isEmpty ? "FilmLab" : clipped
    }

    // MARK: Decoding

    struct DecodeResult: Sendable {
        var name: String?
        var settings: RecipeSettings?
        var unknown: [RawPropertyValue]
    }

    /// Decodes whatever properties are present. Values we don't understand are returned in
    /// `unknown` (and the raw bytes are always preserved by the caller for backups).
    static func decode(_ values: [UInt16: Data]) -> DecodeResult {
        var unknown: [RawPropertyValue] = []
        func flag(_ p: FujiPresetProperty) { if let d = values[p.rawValue] { unknown.append(.init(code: p.rawValue, bytes: d)) } }
        func readU16(_ p: FujiPresetProperty) -> UInt16? {
            guard let d = values[p.rawValue] else { return nil }
            var r = PTPReader(d); return try? r.u16()
        }
        func readI16(_ p: FujiPresetProperty) -> Int16? {
            guard let d = values[p.rawValue] else { return nil }
            var r = PTPReader(d); return try? r.i16()
        }
        /// i16 tenths → Double; sentinel → nil (unset).
        func tenths(_ p: FujiPresetProperty) -> RecipeField<Double> {
            guard let v = readI16(p) else { return .unset }
            if v == fujiUnsetSentinel { return .unset }
            return .value(Double(v) / 10)
        }
        func wholeTenths(_ p: FujiPresetProperty) -> RecipeField<Int> {
            guard let v = readI16(p) else { return .unset }
            if v == fujiUnsetSentinel { return .unset }
            guard v % 10 == 0 else { flag(p); return .unset }
            return .value(Int(v) / 10)
        }
        func reverse<K>(_ table: [K: UInt16], _ p: FujiPresetProperty) -> RecipeField<K> {
            guard let raw = readU16(p) else { return .unset }
            if let k = table.first(where: { $0.value == raw })?.key { return .value(k) }
            flag(p); return .unset
        }

        var name: String?
        if let d = values[FujiPresetProperty.slotName.rawValue] {
            var r = PTPReader(d)
            name = try? r.string()
            if name == nil { flag(.slotName) }
        }

        guard let simRaw = readU16(.filmSimulation) else {
            return DecodeResult(name: name, settings: nil, unknown: unknown)
        }
        guard let sim = filmSimulationCodes.first(where: { $0.value == simRaw })?.key else {
            flag(.filmSimulation)
            return DecodeResult(name: name, settings: nil, unknown: unknown)
        }

        var s = RecipeSettings(filmSimulation: sim)
        s.dRangePriority = reverse(dRangePriorityCodes, .dRangePriority)
        if readU16(.dynamicRange) == 0xFFFF {
            s.dynamicRange = .notApplicable // ILF: reads 0xFFFF while DR Priority is active
        } else {
            s.dynamicRange = reverse(dynamicRangeCodes, .dynamicRange)
        }
        if let g = readU16(.grain) {
            if let (rough, size) = decodeGrain(g) {
                s.grainRoughness = .value(rough)
                s.grainSize = size.map { .value($0) } ?? .notApplicable
            } else { flag(.grain) }
        }
        s.colorChrome = reverse(effectCodes, .colorChrome)
        s.colorChromeFXBlue = reverse(effectCodes, .colorChromeFXBlue)
        s.whiteBalance = reverse(whiteBalanceCodes, .whiteBalance)
        if let k = readU16(.kelvin), s.whiteBalance.concreteValue == .colorTemperature { s.kelvin = .value(Int(k)) }
        if let v = readI16(.wbShiftRed), v != fujiUnsetSentinel { s.wbShiftRed = .value(Int(v)) }
        if let v = readI16(.wbShiftBlue), v != fujiUnsetSentinel { s.wbShiftBlue = .value(Int(v)) }
        s.highlight = tenths(.highlight)
        s.shadow = tenths(.shadow)
        s.color = wholeTenths(.color)
        s.sharpness = wholeTenths(.sharpness)
        s.clarity = wholeTenths(.clarity)
        if let raw = readU16(.highISONR) {
            if let v = highISONRCodes.first(where: { $0.value == raw })?.key { s.highISONR = .value(v) } else { flag(.highISONR) }
        }
        s.monochromaticWarmCool = wholeTenths(.monoWarmCool)
        s.monochromaticMagentaGreen = wholeTenths(.monoMagentaGreen)

        // Disputed/unmodelled properties are surfaced as unknown so the UI can say "preserved".
        for p in FujiPresetProperty.allCases where p.policy == .readOnlyPreserve { flag(p) }

        return DecodeResult(name: name, settings: s.normalized(), unknown: unknown)
    }
}
