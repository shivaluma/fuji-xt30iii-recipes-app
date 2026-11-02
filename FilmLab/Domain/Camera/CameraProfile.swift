import Foundation

/// Identifies a recipe property for capability descriptors, validation, diffs and the PTP map.
enum RecipePropertyKey: String, Codable, CaseIterable, Sendable, Hashable {
    case filmSimulation, grainRoughness, grainSize, colorChrome, colorChromeFXBlue
    case whiteBalance, kelvin, wbShiftRed, wbShiftBlue
    case dynamicRange, dRangePriority, highlight, shadow
    case color, sharpness, highISONR, clarity
    case monochromaticWarmCool, monochromaticMagentaGreen

    var displayName: String {
        switch self {
        case .filmSimulation: "Film Simulation"
        case .grainRoughness: "Grain Effect"
        case .grainSize: "Grain Size"
        case .colorChrome: "Color Chrome Effect"
        case .colorChromeFXBlue: "Color Chrome FX Blue"
        case .whiteBalance: "White Balance"
        case .kelvin: "Color Temperature"
        case .wbShiftRed: "WB Shift R"
        case .wbShiftBlue: "WB Shift B"
        case .dynamicRange: "Dynamic Range"
        case .dRangePriority: "D Range Priority"
        case .highlight: "Highlight"
        case .shadow: "Shadow"
        case .color: "Color"
        case .sharpness: "Sharpness"
        case .highISONR: "High ISO NR"
        case .clarity: "Clarity"
        case .monochromaticWarmCool: "Monochromatic WC"
        case .monochromaticMagentaGreen: "Monochromatic MG"
        }
    }
}

/// A numeric range with a step, e.g. Highlight −2…+4 step 0.5.
struct NumericRange: Codable, Equatable, Hashable, Sendable {
    var min: Double
    var max: Double
    var step: Double

    func contains(_ v: Double) -> Bool {
        guard v >= min - 1e-9, v <= max + 1e-9 else { return false }
        let steps = (v - min) / step
        return abs(steps - steps.rounded()) < 1e-6
    }

    func clamp(_ v: Double) -> Double {
        let c = Swift.min(Swift.max(v, min), max)
        return min + ((c - min) / step).rounded() * step
    }
}

/// Describes one property on one camera model: valid values plus where that knowledge came from.
struct PropertyCapability: Codable, Equatable, Hashable, Sendable {
    var key: RecipePropertyKey
    var isSupported: Bool
    /// For numeric properties.
    var range: NumericRange?
    /// For enumerated properties: FilmLab raw values (e.g. "weak").
    var allowedValues: [String]?
    /// Source of the range/values (manual vs third-party vs device).
    var valuesStatus: VerificationStatus
    /// Whether reading/writing this over PTP has been shown to work.
    var ptpReadStatus: VerificationStatus
    var ptpWriteStatus: VerificationStatus
    var note: String?
}

/// Per-model capabilities. Feature support is modelled at property level, never inferred
/// from sensor generation alone (the generation is only a recipe-family label).
struct CameraProfile: Codable, Equatable, Sendable {
    /// Stable id from `shared/camera-catalog.json`, e.g. "x-t30-iii".
    var catalogID: String
    var modelName: String
    /// Recipe family (follows the processor): X-Processor 5 bodies take X-Trans V recipes.
    var generation: XTransGeneration
    var sensor: String
    var processor: String
    var testedFirmware: [String]
    var filmSimulations: [FilmSimulation]
    var properties: [RecipePropertyKey: PropertyCapability]
    var customSlotCount: Int
    var hasFilmSimulationDial: Bool
    var filmSimulationDialSlots: [FilmSimulationDialSlot]
    var knownQuirks: [String]
    /// Where this body's feature/range data comes from as a whole. Only the X-T30 III is checked
    /// against its manual; the other bodies are community-reported.
    var dataStatus: VerificationStatus

    func capability(_ key: RecipePropertyKey) -> PropertyCapability? { properties[key] }

    func isSupported(_ key: RecipePropertyKey) -> Bool { properties[key]?.isSupported ?? false }

    /// FilmLab only offers (experimental) slot writes where someone has reported the PTP property
    /// map working on that body. Today that is the X-T30 III alone; others are read-only.
    var allowsSlotWrites: Bool {
        (capability(.filmSimulation)?.ptpWriteStatus ?? .notVerified) >= .reportedByThirdParty
    }

    var displayName: String { "\(modelName) · \(generation.displayName)" }
}

extension CameraProfile {
    /// X-T30 III. Ranges from the owner's manual unless marked otherwise. PTP statuses are all
    /// third-party-reported until our own device test passes (docs/device-test-matrix.md).
    static let xt30III: CameraProfile = {
        func cap(_ key: RecipePropertyKey, range: NumericRange? = nil, values: [String]? = nil,
                 source status: VerificationStatus = .verifiedInDocs, note: String? = nil) -> PropertyCapability {
            PropertyCapability(key: key, isSupported: true, range: range, allowedValues: values,
                               valuesStatus: status, ptpReadStatus: .reportedByThirdParty,
                               ptpWriteStatus: .reportedByThirdParty, note: note)
        }
        let effect = EffectLevel.allCases.map(\.rawValue)
        let props: [PropertyCapability] = [
            cap(.filmSimulation, values: FilmSimulation.allCases.map(\.rawValue)),
            cap(.grainRoughness, values: GrainRoughness.allCases.map(\.rawValue)),
            cap(.grainSize, values: GrainSize.allCases.map(\.rawValue)),
            cap(.colorChrome, values: effect),
            cap(.colorChromeFXBlue, values: effect),
            cap(.whiteBalance, values: WhiteBalanceMode.allCases.map(\.rawValue)),
            cap(.kelvin, range: .init(min: 2500, max: 10000, step: 10),
                note: "Manual: 2500–10000 K; rear dial moves in 10 K steps."),
            cap(.wbShiftRed, range: .init(min: -9, max: 9, step: 1), source: .reportedByThirdParty,
                note: "Range from community PTP notes; the manual shows only a grid."),
            cap(.wbShiftBlue, range: .init(min: -9, max: 9, step: 1), source: .reportedByThirdParty,
                note: "Range from community PTP notes; the manual shows only a grid."),
            cap(.dynamicRange, values: DynamicRangeSetting.allCases.map(\.rawValue),
                note: "DR200 needs ISO 320+, DR400 needs ISO 640+. Community notes report presets may not store AUTO."),
            cap(.dRangePriority, values: DRangePriority.allCases.map(\.rawValue),
                note: "Non-OFF values adjust DR and tone curve automatically. One community source reports it is not stored in presets."),
            cap(.highlight, range: .init(min: -2, max: 4, step: 0.5), source: .reportedByThirdParty,
                note: "Manual: −2…+4. Half steps are reported by community PTP notes (value × 10 on the wire); not in manual text."),
            cap(.shadow, range: .init(min: -2, max: 4, step: 0.5), source: .reportedByThirdParty,
                note: "Manual: −2…+4. Half steps are reported by community PTP notes; not in manual text."),
            cap(.color, range: .init(min: -4, max: 4, step: 1)),
            cap(.sharpness, range: .init(min: -4, max: 4, step: 1)),
            cap(.highISONR, range: .init(min: -4, max: 4, step: 1)),
            cap(.clarity, range: .init(min: -5, max: 5, step: 1),
                note: "Manual: non-zero clarity slows saving; HEIF disables clarity."),
            cap(.monochromaticWarmCool, range: .init(min: -18, max: 18, step: 1), source: .reportedByThirdParty,
                note: "ACROS/MONOCHROME only. Range from community PTP notes (×10 on the wire); not in manual text."),
            cap(.monochromaticMagentaGreen, range: .init(min: -18, max: 18, step: 1), source: .reportedByThirdParty,
                note: "ACROS/MONOCHROME only. Range from community PTP notes; not in manual text."),
        ]
        return CameraProfile(
            catalogID: "x-t30-iii",
            modelName: "X-T30 III",
            generation: .v,
            sensor: "X-Trans CMOS 4 (26.1 MP, BSI)",
            processor: "X-Processor 5",
            testedFirmware: [],
            filmSimulations: FilmSimulation.allCases,
            properties: Dictionary(uniqueKeysWithValues: props.map { ($0.key, $0) }),
            customSlotCount: 7,
            hasFilmSimulationDial: true,
            filmSimulationDialSlots: FilmSimulationDialSlot.allCases,
            knownQuirks: [
                "A FILM SIMULATION saved in a C bank takes effect only when the film simulation dial is set to C (manual).",
                "FS1–FS3 are dial positions with separate FS RECIPE settings; writing a C slot does not program them.",
                "FS RECIPE is not applied when the AUTO lever is engaged (manual).",
                "Community report: grain OFF may read back as a vendor-specific code that encodes the last size.",
                "Community report: DR AUTO and D RANGE PRIORITY may not be stored in custom presets.",
            ],
            dataStatus: .verifiedInDocs
        )
    }()
}

// MARK: - Validation

struct ValidationIssue: Equatable, Hashable, Sendable, Identifiable {
    enum Severity: String, Sendable { case error, warning, info }
    var key: RecipePropertyKey
    var severity: Severity
    var message: String
    /// True when the issue is about what this camera body can do (unsupported film simulation,
    /// setting or value), as opposed to dependency hints that apply to every body.
    var isCapability = false
    var id: String { "\(key.rawValue)-\(message)" }
}

/// Declarative capability validation: explains *why* a value is unsupported instead of
/// silently dropping it.
struct RecipeValidator: Sendable {
    let profile: CameraProfile

    func validate(_ s: RecipeSettings) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func err(_ k: RecipePropertyKey, _ m: String) { issues.append(.init(key: k, severity: .error, message: m)) }
        func warn(_ k: RecipePropertyKey, _ m: String) { issues.append(.init(key: k, severity: .warning, message: m)) }
        func capErr(_ k: RecipePropertyKey, _ m: String) { issues.append(.init(key: k, severity: .error, message: m, isCapability: true)) }
        /// A setting this body doesn't have, holding its neutral value: nothing is lost by skipping it.
        func capInfo(_ k: RecipePropertyKey, _ m: String) { issues.append(.init(key: k, severity: .info, message: m, isCapability: true)) }
        // Per-field "third-party range" notes only make sense on the manual-checked reference body;
        // other bodies get one summary note below.
        let perFieldSourceNotes = profile.dataStatus >= .verifiedInDocs

        if !profile.filmSimulations.contains(s.filmSimulation) {
            capErr(.filmSimulation, "\(s.filmSimulation.displayName) is not available on \(profile.modelName).")
        }

        func checkNumber(_ k: RecipePropertyKey, _ v: Double?) {
            guard let v else { return }
            guard let cap = profile.capability(k), cap.isSupported else {
                if v == 0 { capInfo(k, "\(profile.modelName) has no \(k.displayName) setting; 0 is the default, so nothing changes.") }
                else { capErr(k, "\(k.displayName) is not available on \(profile.modelName).") }
                return
            }
            if let r = cap.range, !r.contains(v) {
                capErr(k, "\(k.displayName) \(Self.format(v)) is outside \(Self.format(r.min))…\(Self.format(r.max)) (step \(Self.format(r.step))) on \(profile.modelName).")
            } else if perFieldSourceNotes, cap.valuesStatus == .reportedByThirdParty {
                issues.append(.init(key: k, severity: .info, message: "\(k.displayName) range is reported by a third party, not the manual."))
            }
        }
        func checkEnum(_ k: RecipePropertyKey, _ raw: String?, neutral: String? = nil) {
            guard let raw else { return }
            guard let cap = profile.capability(k), cap.isSupported else {
                if raw == neutral { capInfo(k, "\(profile.modelName) has no \(k.displayName) setting; “\(raw)” is the default, so nothing changes.") }
                else { capErr(k, "\(k.displayName) is not available on \(profile.modelName).") }
                return
            }
            if let allowed = cap.allowedValues, !allowed.contains(raw) {
                capErr(k, "\(k.displayName) value “\(raw)” is not supported on \(profile.modelName).")
            }
        }

        checkEnum(.grainRoughness, s.grainRoughness.concreteValue?.rawValue)
        checkEnum(.grainSize, s.grainSize.concreteValue?.rawValue, neutral: GrainSize.small.rawValue)
        checkEnum(.colorChrome, s.colorChrome.concreteValue?.rawValue, neutral: EffectLevel.off.rawValue)
        checkEnum(.colorChromeFXBlue, s.colorChromeFXBlue.concreteValue?.rawValue, neutral: EffectLevel.off.rawValue)
        checkEnum(.whiteBalance, s.whiteBalance.concreteValue?.rawValue)
        checkEnum(.dynamicRange, s.dynamicRange.concreteValue?.rawValue)
        checkEnum(.dRangePriority, s.dRangePriority.concreteValue?.rawValue)
        checkNumber(.kelvin, s.kelvin.concreteValue.map(Double.init))
        checkNumber(.wbShiftRed, s.wbShiftRed.concreteValue.map(Double.init))
        checkNumber(.wbShiftBlue, s.wbShiftBlue.concreteValue.map(Double.init))
        checkNumber(.highlight, s.highlight.concreteValue)
        checkNumber(.shadow, s.shadow.concreteValue)
        checkNumber(.color, s.color.concreteValue.map(Double.init))
        checkNumber(.sharpness, s.sharpness.concreteValue.map(Double.init))
        checkNumber(.highISONR, s.highISONR.concreteValue.map(Double.init))
        checkNumber(.clarity, s.clarity.concreteValue.map(Double.init))
        checkNumber(.monochromaticWarmCool, s.monochromaticWarmCool.concreteValue.map(Double.init))
        checkNumber(.monochromaticMagentaGreen, s.monochromaticMagentaGreen.concreteValue.map(Double.init))

        // Dependency checks on un-normalized input (e.g. imported JSON).
        if s.whiteBalance.concreteValue != .colorTemperature, s.kelvin.isSet {
            warn(.kelvin, "Color temperature is ignored unless White Balance is COLOR TEMPERATURE.")
        }
        if s.whiteBalance.concreteValue == .colorTemperature, !s.kelvin.isSet {
            err(.kelvin, "COLOR TEMPERATURE white balance needs a Kelvin value.")
        }
        if s.filmSimulation.isMonochrome, s.color.isSet {
            warn(.color, "COLOR does not apply to monochrome simulations.")
        }
        if !s.filmSimulation.supportsMonochromaticColor,
           s.monochromaticWarmCool.isSet || s.monochromaticMagentaGreen.isSet {
            warn(.monochromaticWarmCool, "MONOCHROMATIC COLOR applies only to ACROS and MONOCHROME.")
        }
        if !s.isToneAndDRManual, s.highlight.isSet || s.shadow.isSet || s.dynamicRange.isSet {
            warn(.dRangePriority, "D RANGE PRIORITY adjusts tone curve and dynamic range automatically; manual values are ignored.")
        }
        if s.grainRoughness.concreteValue == .off, s.grainSize.isSet {
            warn(.grainSize, "Grain size is ignored when grain is OFF.")
        }
        if !perFieldSourceNotes {
            issues.append(.init(key: .filmSimulation, severity: .info,
                                message: "\(profile.modelName) feature support and ranges are community-reported, not checked by FilmLab against its manual."))
        }
        return issues
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
