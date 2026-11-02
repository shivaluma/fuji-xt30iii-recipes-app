import Foundation

/// Recipe family as the community uses it. It follows the *processor's* feature set, so
/// X-Processor 5 bodies with an X-Trans CMOS 4 sensor (X-T30 III, X-S20, X-M5) take X-Trans V
/// recipes. X-Trans IV recipes generally run on X-Trans V bodies; the reverse needs REALA ACE /
/// NOSTALGIC Neg. to be absent. See docs/cameras.md.
enum XTransGeneration: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case v = "V"
    case iv = "IV"

    var id: String { rawValue }
    var displayName: String { "X-Trans \(rawValue)" }
    var processor: String { self == .v ? "X-Processor 5" : "X-Processor 4" }

    /// "X-Trans IV", "X-TRANS 5", "X-Trans CMOS 4" … in free text. Roman III and below never match.
    static func detect(in text: String) -> XTransGeneration? {
        let pattern = #"X[\s-]?TRANS[\s-]?(?:CMOS[\s-]?)?(IV|V|4|5)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        switch text[r].uppercased() {
        case "IV", "4": return .iv
        case "V", "5": return .v
        default: return nil
        }
    }
}

/// One camera body from `shared/camera-catalog.json` (mirrored here; `CameraCatalogTests`
/// decodes the JSON and checks this mirror matches it exactly).
struct CameraModelInfo: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var aliases: [String]
    var sensor: String
    var processor: String
    var generation: XTransGeneration
    var filmSimulations: [FilmSimulation]
    var unsupported: Set<RecipePropertyKey>
    var rangeOverrides: [RecipePropertyKey: NumericRange]
    var customSlots: Int
    var hasFilmSimulationDial: Bool
    /// Source of the feature/range data for this body.
    var status: VerificationStatus
    /// Whether PTP slot read/write has been reported to work on this body.
    var ptp: VerificationStatus
    var notes: [String]

    /// The full capability profile used by validation, the Tune panel and the Camera tab.
    var profile: CameraProfile { CameraCatalog.profiles[id] ?? buildProfile() }

    fileprivate func buildProfile() -> CameraProfile {
        if id == CameraProfile.xt30III.catalogID { return .xt30III }
        func cap(_ key: RecipePropertyKey, values: [String]? = nil) -> PropertyCapability {
            let supported = !unsupported.contains(key)
            let range = supported ? (rangeOverrides[key] ?? CameraCatalog.baseRanges[key]) : nil
            return PropertyCapability(
                key: key, isSupported: supported, range: range, allowedValues: supported ? values : nil,
                valuesStatus: status, ptpReadStatus: ptp, ptpWriteStatus: ptp,
                note: supported ? (rangeOverrides[key] != nil ? "Model-specific range (community-reported)." : nil)
                                : "Not available on \(name) (community-reported).")
        }
        let effect = EffectLevel.allCases.map(\.rawValue)
        let props: [PropertyCapability] = [
            cap(.filmSimulation, values: filmSimulations.map(\.rawValue)),
            cap(.grainRoughness, values: GrainRoughness.allCases.map(\.rawValue)),
            cap(.grainSize, values: GrainSize.allCases.map(\.rawValue)),
            cap(.colorChrome, values: effect),
            cap(.colorChromeFXBlue, values: effect),
            cap(.whiteBalance, values: WhiteBalanceMode.allCases.map(\.rawValue)),
            cap(.kelvin), cap(.wbShiftRed), cap(.wbShiftBlue),
            cap(.dynamicRange, values: DynamicRangeSetting.allCases.map(\.rawValue)),
            cap(.dRangePriority, values: DRangePriority.allCases.map(\.rawValue)),
            cap(.highlight), cap(.shadow), cap(.color), cap(.sharpness), cap(.highISONR), cap(.clarity),
            cap(.monochromaticWarmCool), cap(.monochromaticMagentaGreen),
        ]
        return CameraProfile(
            catalogID: id,
            modelName: name,
            generation: generation,
            sensor: sensor,
            processor: processor,
            testedFirmware: [],
            filmSimulations: filmSimulations,
            properties: Dictionary(uniqueKeysWithValues: props.map { ($0.key, $0) }),
            customSlotCount: customSlots,
            hasFilmSimulationDial: hasFilmSimulationDial,
            filmSimulationDialSlots: hasFilmSimulationDial ? FilmSimulationDialSlot.allCases : [],
            knownQuirks: notes,
            dataStatus: status
        )
    }
}

/// Compatibility of one recipe with one camera body.
enum RecipeCompatibility: Equatable, Sendable {
    /// Every setting the recipe uses exists on the body with the recipe's values.
    case supported
    /// The film simulation exists, but some settings/values don't — the look will differ a bit.
    case worksWithChanges([ValidationIssue])
    /// The body doesn't have the recipe's film simulation.
    case notAvailable(String)

    var label: String {
        switch self {
        case .supported: "Works"
        case .worksWithChanges: "Works with changes"
        case .notAvailable: "Not available"
        }
    }

    var isUsable: Bool { if case .notAvailable = self { false } else { true } }

    static func evaluate(_ settings: RecipeSettings, on profile: CameraProfile) -> RecipeCompatibility {
        let issues = RecipeValidator(profile: profile).validate(settings).filter(\.isCapability)
        if let sim = issues.first(where: { $0.key == .filmSimulation && $0.severity == .error }) {
            return .notAvailable(sim.message)
        }
        let blocking = issues.filter { $0.severity != .info }
        return blocking.isEmpty ? .supported : .worksWithChanges(blocking)
    }
}

enum CameraCatalog {
    static let baseRanges: [RecipePropertyKey: NumericRange] = [
        .kelvin: .init(min: 2500, max: 10000, step: 10),
        .wbShiftRed: .init(min: -9, max: 9, step: 1),
        .wbShiftBlue: .init(min: -9, max: 9, step: 1),
        .highlight: .init(min: -2, max: 4, step: 0.5),
        .shadow: .init(min: -2, max: 4, step: 0.5),
        .color: .init(min: -4, max: 4, step: 1),
        .sharpness: .init(min: -4, max: 4, step: 1),
        .highISONR: .init(min: -4, max: 4, step: 1),
        .clarity: .init(min: -5, max: 5, step: 1),
        .monochromaticWarmCool: .init(min: -18, max: 18, step: 1),
        .monochromaticMagentaGreen: .init(min: -18, max: 18, step: 1),
    ]

    /// Named film simulation sets (keys match the JSON's `filmSimulationSets`).
    static let filmSimulationSets: [String: [FilmSimulation]] = {
        let xp5 = FilmSimulation.allCases
        let xp4 = xp5.filter { $0 != .realaAce && $0 != .nostalgicNeg }
        let xp4NoBleach = xp4.filter { $0 != .eternaBleachBypass }
        let xp4Early = xp4NoBleach.filter { $0 != .classicNeg }
        return ["xp5": xp5, "xp4": xp4, "xp4NoBleach": xp4NoBleach, "xp4Early": xp4Early]
    }()

    private static func body(
        _ id: String, _ name: String, aliases: [String], sensor: String, processor: String, _ generation: XTransGeneration,
        sims: String, unsupported: Set<RecipePropertyKey> = [], ranges: [RecipePropertyKey: NumericRange] = [:],
        dial: Bool = false, status: VerificationStatus = .reportedByThirdParty, ptp: VerificationStatus = .notVerified,
        notes: [String] = []
    ) -> CameraModelInfo {
        CameraModelInfo(id: id, name: name, aliases: aliases, sensor: sensor, processor: processor, generation: generation,
                        filmSimulations: filmSimulationSets[sims] ?? [], unsupported: unsupported, rangeOverrides: ranges,
                        customSlots: 7, hasFilmSimulationDial: dial, status: status, ptp: ptp, notes: notes)
    }

    private static let realaFirmware = "REALA ACE arrived in a firmware update; update the camera if it's missing."
    private static let noBleach = "No ETERNA BLEACH BYPASS (community reports)."
    private static let earlyIV = "Early X-Trans IV: no CLASSIC Neg., ETERNA BLEACH BYPASS, Color Chrome FX Blue, Clarity or grain size; Highlight/Shadow in whole steps (community reports)."
    private static let earlyUnsupported: Set<RecipePropertyKey> = [.colorChromeFXBlue, .clarity, .grainSize, .monochromaticMagentaGreen]
    private static let wholeSteps: [RecipePropertyKey: NumericRange] = [
        .highlight: .init(min: -2, max: 4, step: 1), .shadow: .init(min: -2, max: 4, step: 1),
    ]
    private static let xtrans4 = "X-Trans CMOS 4 (26.1 MP)"
    private static let xtrans5HR = "X-Trans CMOS 5 HR (40.2 MP)"

    /// Catalog order: X-Trans V bodies first (reference body on top), then X-Trans IV.
    static let all: [CameraModelInfo] = [
        body("x-t30-iii", "X-T30 III", aliases: ["XT30 III", "X-T30III", "XT30III", "X-T30 Mark III"], sensor: xtrans4, processor: "X-Processor 5", .v,
             sims: "xp5", dial: true, status: .verifiedInDocs, ptp: .reportedByThirdParty,
             notes: ["FilmLab's reference body: ranges come from the owner's manual."]),
        body("x-m5", "X-M5", aliases: ["XM5"], sensor: xtrans4, processor: "X-Processor 5", .v, sims: "xp5", dial: true),
        body("x-s20", "X-S20", aliases: ["XS20"], sensor: xtrans4, processor: "X-Processor 5", .v, sims: "xp5", notes: [realaFirmware]),
        body("x-t50", "X-T50", aliases: ["XT50"], sensor: xtrans5HR, processor: "X-Processor 5", .v, sims: "xp5", dial: true),
        body("x-e5", "X-E5", aliases: ["XE5"], sensor: xtrans5HR, processor: "X-Processor 5", .v, sims: "xp5", dial: true),
        body("x100vi", "X100VI", aliases: ["X100 VI", "X100V6"], sensor: xtrans5HR, processor: "X-Processor 5", .v, sims: "xp5"),
        body("x-t5", "X-T5", aliases: ["XT5"], sensor: xtrans5HR, processor: "X-Processor 5", .v, sims: "xp5", notes: [realaFirmware]),
        body("x-h2", "X-H2", aliases: ["XH2"], sensor: xtrans5HR, processor: "X-Processor 5", .v, sims: "xp5", notes: [realaFirmware]),
        body("x-h2s", "X-H2S", aliases: ["XH2S", "X-H2 S"], sensor: "X-Trans CMOS 5 HS (26.1 MP, stacked)", processor: "X-Processor 5", .v,
             sims: "xp5", notes: [realaFirmware]),
        body("x-t30-ii", "X-T30 II", aliases: ["XT30 II", "X-T30II", "XT30II", "X-T30 Mark II"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4"),
        body("x-t4", "X-T4", aliases: ["XT4"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4"),
        body("x-s10", "X-S10", aliases: ["XS10"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4"),
        body("x-e4", "X-E4", aliases: ["XE4"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4"),
        body("x100v", "X100V", aliases: ["X100 V"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4NoBleach", notes: [noBleach]),
        body("x-pro3", "X-Pro3", aliases: ["XPro3", "X-Pro 3"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4NoBleach", notes: [noBleach]),
        body("x-t3", "X-T3", aliases: ["XT3"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4Early",
             unsupported: earlyUnsupported, ranges: wholeSteps, notes: [earlyIV]),
        body("x-t30", "X-T30", aliases: ["XT30"], sensor: xtrans4, processor: "X-Processor 4", .iv, sims: "xp4Early",
             unsupported: earlyUnsupported, ranges: wholeSteps, notes: [earlyIV]),
    ]

    static let reference: CameraModelInfo = all[0]

    fileprivate static let profiles: [String: CameraProfile] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.buildProfile()) })

    static func info(id: String) -> CameraModelInfo? { all.first { $0.id == id } }

    static func grouped() -> [(generation: XTransGeneration, cameras: [CameraModelInfo])] {
        XTransGeneration.allCases.map { g in (g, all.filter { $0.generation == g }) }
    }

    // MARK: Recognition

    private static func compact(_ s: String) -> String {
        s.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// (key, camera) pairs, longest key first so "X-T30 III" beats "X-T30 II" beats "X-T30".
    private static let keys: [(key: String, camera: CameraModelInfo)] = {
        var seen = Set<String>()
        var out: [(String, CameraModelInfo)] = []
        for c in all {
            for k in [c.name] + c.aliases {
                let n = compact(k)
                if !n.isEmpty, seen.insert(n).inserted { out.append((n, c)) }
            }
        }
        return out.enumerated().sorted { a, b in
            a.element.0.count != b.element.0.count ? a.element.0.count > b.element.0.count : a.offset < b.offset
        }.map { ($0.element.0, $0.element.1) }
    }()

    private static let matchers: [(NSRegularExpression, CameraModelInfo)] = keys.compactMap { k, c in
        let body = k.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[ -]?")
        return (try? NSRegularExpression(pattern: "(?<![A-Z0-9])\(body)(?![A-Z0-9])")).map { ($0, c) }
    }

    /// Finds a catalog body in free text ("FUJIFILM X-T30 Mark III", "made on my xt5", a PTP model
    /// string). Returns nil for unknown bodies.
    static func recognize(_ text: String) -> CameraModelInfo? {
        var t = text.uppercased()
        t = t.replacingOccurrences(of: #"\bFUJIFILM\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\bMARK\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let range = NSRange(t.startIndex..., in: t)
        for (re, camera) in matchers where re.firstMatch(in: t, range: range) != nil { return camera }
        return nil
    }

    /// Capability profile for a model name, or nil when the body isn't in the catalog.
    static func profile(for model: String) -> CameraProfile? { recognize(model)?.profile }
}

extension FilmRecipe {
    /// Explicit tag, else REALA ACE / NOSTALGIC Neg. ⇒ X-Trans V, else the generation of the first
    /// recognised camera in `compatibleCameras`, else unknown. Same rule as the web.
    ///
    /// Older recipes always got "X-T30 III" added by default, so it only counts when it is the sole
    /// entry: ["X-T30 III", "X100V"] infers IV from the X100V.
    var inferredGeneration: XTransGeneration? {
        if let xTransGeneration { return xTransGeneration }
        if settings.filmSimulation == .realaAce || settings.filmSimulation == .nostalgicNeg { return .v }
        let reference = CameraProfile.xt30III.catalogID
        let others = compatibleCameras.filter { CameraCatalog.recognize($0)?.id != reference }
        let candidates = others.isEmpty ? compatibleCameras : others
        return candidates.lazy.compactMap { CameraCatalog.recognize($0)?.generation }.first
    }

    func compatibility(with profile: CameraProfile) -> RecipeCompatibility {
        RecipeCompatibility.evaluate(settings, on: profile)
    }
}
