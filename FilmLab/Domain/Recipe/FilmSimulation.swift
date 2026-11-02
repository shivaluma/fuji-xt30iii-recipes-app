import Foundation

/// Film simulations listed for still photography in the X-T30 III owner's manual
/// (IMAGE QUALITY SETTING › FILM SIMULATION). See docs/research.md §2.
///
/// `AUTO` is intentionally not modelled: the manual says it is only available when the
/// AUTO mode selector lever is engaged, so it is not a recipe value.
///
/// Raw values are FilmLab's own stable identifiers used in the JSON schema. They are NOT
/// PTP codes; see `FujiPTPPropertyTable` for the third-party-reported wire codes.
enum FilmSimulation: String, Codable, CaseIterable, Identifiable, Sendable {
    case provia
    case velvia
    case astia
    case classicChrome
    case realaAce
    case proNegHi
    case proNegStd
    case classicNeg
    case nostalgicNeg
    case eterna
    case eternaBleachBypass
    case acros
    case acrosYe
    case acrosR
    case acrosG
    case monochrome
    case monochromeYe
    case monochromeR
    case monochromeG
    case sepia

    var id: String { rawValue }

    /// Names as printed in the manual. Film simulation names are FUJIFILM trademarks and are
    /// used descriptively to identify camera settings.
    var displayName: String {
        switch self {
        case .provia: "PROVIA/STANDARD"
        case .velvia: "Velvia/VIVID"
        case .astia: "ASTIA/SOFT"
        case .classicChrome: "CLASSIC CHROME"
        case .realaAce: "REALA ACE"
        case .proNegHi: "PRO Neg. Hi"
        case .proNegStd: "PRO Neg. Std"
        case .classicNeg: "CLASSIC Neg."
        case .nostalgicNeg: "NOSTALGIC Neg."
        case .eterna: "ETERNA/CINEMA"
        case .eternaBleachBypass: "ETERNA BLEACH BYPASS"
        case .acros: "ACROS"
        case .acrosYe: "ACROS+Ye FILTER"
        case .acrosR: "ACROS+R FILTER"
        case .acrosG: "ACROS+G FILTER"
        case .monochrome: "MONOCHROME"
        case .monochromeYe: "MONOCHROME+Ye FILTER"
        case .monochromeR: "MONOCHROME+R FILTER"
        case .monochromeG: "MONOCHROME+G FILTER"
        case .sepia: "SEPIA"
        }
    }

    /// Short label for compact pickers.
    var shortName: String {
        switch self {
        case .provia: "Provia"
        case .velvia: "Velvia"
        case .astia: "Astia"
        case .classicChrome: "Cl. Chrome"
        case .realaAce: "Reala Ace"
        case .proNegHi: "Neg. Hi"
        case .proNegStd: "Neg. Std"
        case .classicNeg: "Cl. Neg"
        case .nostalgicNeg: "Nostalgic"
        case .eterna: "Eterna"
        case .eternaBleachBypass: "Bleach Bypass"
        case .acros: "Acros"
        case .acrosYe: "Acros Ye"
        case .acrosR: "Acros R"
        case .acrosG: "Acros G"
        case .monochrome: "Mono"
        case .monochromeYe: "Mono Ye"
        case .monochromeR: "Mono R"
        case .monochromeG: "Mono G"
        case .sepia: "Sepia"
        }
    }

    /// True for every black-and-white or toned simulation (colour settings don't apply).
    var isMonochrome: Bool {
        switch self {
        case .acros, .acrosYe, .acrosR, .acrosG,
             .monochrome, .monochromeYe, .monochromeR, .monochromeG, .sepia:
            true
        default:
            false
        }
    }

    /// The manual says MONOCHROMATIC COLOR applies only to ACROS and MONOCHROME (incl. filters).
    var supportsMonochromaticColor: Bool { isMonochrome && self != .sepia }

    var colorFilter: MonochromeFilter? {
        switch self {
        case .acrosYe, .monochromeYe: .yellow
        case .acrosR, .monochromeR: .red
        case .acrosG, .monochromeG: .green
        default: nil
        }
    }
}

enum MonochromeFilter: String, Codable, Sendable {
    case yellow, red, green
}
