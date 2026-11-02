import Foundation
import CryptoKit

// MARK: - Value enums (values per X-T30 III manual; see docs/research.md §2)

enum EffectLevel: String, Codable, CaseIterable, Sendable, Hashable {
    case off, weak, strong
    var displayName: String { rawValue.uppercased() }
}

enum GrainRoughness: String, Codable, CaseIterable, Sendable, Hashable {
    case off, weak, strong
    var displayName: String { rawValue.uppercased() }
}

enum GrainSize: String, Codable, CaseIterable, Sendable, Hashable {
    case small, large
    var displayName: String { rawValue.uppercased() }
}

enum WhiteBalanceMode: String, Codable, CaseIterable, Sendable, Hashable {
    case autoWhitePriority
    case auto
    case autoAmbiencePriority
    case custom1, custom2, custom3
    case colorTemperature
    case daylight
    case shade
    case fluorescent1, fluorescent2, fluorescent3
    case incandescent
    case underwater

    var displayName: String {
        switch self {
        case .autoWhitePriority: "WHITE PRIORITY"
        case .auto: "AUTO"
        case .autoAmbiencePriority: "AMBIENCE PRIORITY"
        case .custom1: "CUSTOM 1"
        case .custom2: "CUSTOM 2"
        case .custom3: "CUSTOM 3"
        case .colorTemperature: "COLOR TEMPERATURE"
        case .daylight: "DAYLIGHT"
        case .shade: "SHADE"
        case .fluorescent1: "FLUORESCENT 1"
        case .fluorescent2: "FLUORESCENT 2"
        case .fluorescent3: "FLUORESCENT 3"
        case .incandescent: "INCANDESCENT"
        case .underwater: "UNDERWATER"
        }
    }

    /// Nominal correlated colour temperature used ONLY by the approximate on-device renderer.
    /// These are FilmLab assumptions, not Fujifilm specifications. `nil` = scene-dependent
    /// (auto / custom), in which case the approximate renderer leaves the source neutral.
    var approximatePreviewKelvin: Double? {
        switch self {
        case .daylight: 5500
        case .shade: 7500
        case .fluorescent1: 6500
        case .fluorescent2: 5000
        case .fluorescent3: 4000
        case .incandescent: 3000
        case .underwater: 6000
        case .auto, .autoWhitePriority, .autoAmbiencePriority, .custom1, .custom2, .custom3, .colorTemperature:
            nil
        }
    }
}

enum DynamicRangeSetting: String, Codable, CaseIterable, Sendable, Hashable {
    case auto, dr100, dr200, dr400
    var displayName: String {
        switch self {
        case .auto: "AUTO"
        case .dr100: "DR100%"
        case .dr200: "DR200%"
        case .dr400: "DR400%"
        }
    }
    /// Manual: DR200 needs ISO 320+, DR400 needs ISO 640+.
    var minimumISO: Int? {
        switch self {
        case .dr200: 320
        case .dr400: 640
        default: nil
        }
    }
}

enum DRangePriority: String, Codable, CaseIterable, Sendable, Hashable {
    case off, weak, strong, auto
    var displayName: String { rawValue.uppercased() }
    var minimumISO: Int? {
        switch self {
        case .weak: 320
        case .strong: 640
        default: nil
        }
    }
}

// MARK: - Settings

/// Typed, versioned still-image recipe settings.
///
/// Dependency rules (`normalized()`) come from the X-T30 III manual where stated, and are
/// documented inline. Ranges live in `CameraProfile` so other models can differ.
struct RecipeSettings: Codable, Equatable, Hashable, Sendable {
    var filmSimulation: FilmSimulation

    var grainRoughness: RecipeField<GrainRoughness> = .unset
    var grainSize: RecipeField<GrainSize> = .unset
    var colorChrome: RecipeField<EffectLevel> = .unset
    var colorChromeFXBlue: RecipeField<EffectLevel> = .unset

    var whiteBalance: RecipeField<WhiteBalanceMode> = .unset
    /// 2500–10000 K, only when `whiteBalance == .colorTemperature`.
    var kelvin: RecipeField<Int> = .unset
    var wbShiftRed: RecipeField<Int> = .unset
    var wbShiftBlue: RecipeField<Int> = .unset

    var dynamicRange: RecipeField<DynamicRangeSetting> = .unset
    var dRangePriority: RecipeField<DRangePriority> = .unset

    var highlight: RecipeField<Double> = .unset
    var shadow: RecipeField<Double> = .unset
    var color: RecipeField<Int> = .unset
    var sharpness: RecipeField<Int> = .unset
    var highISONR: RecipeField<Int> = .unset
    var clarity: RecipeField<Int> = .unset

    var monochromaticWarmCool: RecipeField<Int> = .unset
    var monochromaticMagentaGreen: RecipeField<Int> = .unset

    /// Recipe author's suggested exposure compensation. NOT a camera preset property (the
    /// exposure dial isn't stored in a C slot); used for the approximate preview and as a note.
    var suggestedExposureCompensation: RecipeField<Double> = .unset

    init(filmSimulation: FilmSimulation) {
        self.filmSimulation = filmSimulation
    }

    /// A neutral baseline that a user can start editing from.
    static func neutral(_ sim: FilmSimulation = .provia) -> RecipeSettings {
        var s = RecipeSettings(filmSimulation: sim)
        s.grainRoughness = .value(.off)
        s.colorChrome = .value(.off)
        s.colorChromeFXBlue = .value(.off)
        s.whiteBalance = .value(.auto)
        s.wbShiftRed = .value(0)
        s.wbShiftBlue = .value(0)
        s.dynamicRange = .value(.dr100)
        s.dRangePriority = .value(.off)
        s.highlight = .value(0)
        s.shadow = .value(0)
        s.color = .value(0)
        s.sharpness = .value(0)
        s.highISONR = .value(0)
        s.clarity = .value(0)
        s.monochromaticWarmCool = .value(0)
        s.monochromaticMagentaGreen = .value(0)
        return s.normalized()
    }

    // MARK: Dependencies

    var isKelvinApplicable: Bool { whiteBalance.concreteValue == .colorTemperature }
    var isGrainSizeApplicable: Bool { grainRoughness.concreteValue != .off }
    var isColorApplicable: Bool { !filmSimulation.isMonochrome }
    var isMonochromaticColorApplicable: Bool { filmSimulation.supportsMonochromaticColor }
    /// Manual: any D RANGE PRIORITY other than OFF adjusts TONE CURVE and DYNAMIC RANGE
    /// automatically; manual adjustment requires OFF.
    var isToneAndDRManual: Bool {
        guard let drp = dRangePriority.concreteValue else { return true }
        return drp == .off
    }

    /// Applies dependency rules: inapplicable fields become `.notApplicable`; fields that
    /// were `.notApplicable` but are applicable again become `.unset` (never invented values).
    func normalized() -> RecipeSettings {
        var s = self
        func apply<T>(_ field: inout RecipeField<T>, applicable: Bool) {
            if applicable {
                if field == .notApplicable { field = .unset }
            } else {
                field = .notApplicable
            }
        }
        apply(&s.kelvin, applicable: s.isKelvinApplicable)
        apply(&s.grainSize, applicable: s.isGrainSizeApplicable)
        apply(&s.color, applicable: s.isColorApplicable)
        apply(&s.monochromaticWarmCool, applicable: s.isMonochromaticColorApplicable)
        apply(&s.monochromaticMagentaGreen, applicable: s.isMonochromaticColorApplicable)
        let manual = s.isToneAndDRManual
        apply(&s.dynamicRange, applicable: manual)
        apply(&s.highlight, applicable: manual)
        apply(&s.shadow, applicable: manual)
        return s
    }

    // MARK: Fingerprint

    /// Stable content hash used in cache keys. Uses sorted-key JSON so field order and
    /// struct layout don't matter, then SHA-256.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Tolerant decoding

extension RecipeSettings {
    /// Missing keys decode as `.unset` so older/newer JSON files and partial third-party
    /// imports load without inventing values. Only `filmSimulation` is required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(filmSimulation: try c.decode(FilmSimulation.self, forKey: .filmSimulation))
        func f<T>(_ key: CodingKeys) throws -> RecipeField<T> {
            try c.decodeIfPresent(RecipeField<T>.self, forKey: key) ?? .unset
        }
        grainRoughness = try f(.grainRoughness)
        grainSize = try f(.grainSize)
        colorChrome = try f(.colorChrome)
        colorChromeFXBlue = try f(.colorChromeFXBlue)
        whiteBalance = try f(.whiteBalance)
        kelvin = try f(.kelvin)
        wbShiftRed = try f(.wbShiftRed)
        wbShiftBlue = try f(.wbShiftBlue)
        dynamicRange = try f(.dynamicRange)
        dRangePriority = try f(.dRangePriority)
        highlight = try f(.highlight)
        shadow = try f(.shadow)
        color = try f(.color)
        sharpness = try f(.sharpness)
        highISONR = try f(.highISONR)
        clarity = try f(.clarity)
        monochromaticWarmCool = try f(.monochromaticWarmCool)
        monochromaticMagentaGreen = try f(.monochromaticMagentaGreen)
        suggestedExposureCompensation = try f(.suggestedExposureCompensation)
    }
}
