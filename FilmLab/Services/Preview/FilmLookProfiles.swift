import Foundation
import simd

/// FilmLab's ORIGINAL placeholder look profiles.
///
/// ⚠️ These are hand-tuned approximations written for this project. They are NOT derived from
/// Fujifilm's proprietary processing, NOT calibrated against camera output, and NOT
/// pixel-accurate. They exist so each simulation is visibly distinct and recognisable in
/// character. Replace with calibrated LUTs via `docs/architecture.md › Calibration`.
struct FilmLookProfile: Sendable, Equatable {
    /// S-curve strength: >0 adds contrast, <0 flattens.
    var contrast: Float = 0
    var saturation: Float = 1
    /// Lifts blacks (0…0.1). Gives a "fade".
    var blackLift: Float = 0
    /// Highlight roll-off: compresses values near white (0…0.4).
    var highlightRolloff: Float = 0.05
    /// Additive tint in shadows/highlights (display-referred RGB).
    var shadowTint: SIMD3<Float> = .zero
    var highlightTint: SIMD3<Float> = .zero
    /// Per-hue-band saturation multipliers and hue shifts (degrees).
    var hueBands: [HueBand] = []
    /// Monochrome channel mix (nil = colour simulation).
    var monoMix: SIMD3<Float>? = nil
    /// Colour applied to monochrome result in highlights/shadows (sepia, Acros warmth).
    var monoTone: SIMD3<Float> = .zero

    struct HueBand: Sendable, Equatable {
        var center: Float     // degrees
        var width: Float      // degrees (half-width of the falloff)
        var saturation: Float // multiplier
        var hueShift: Float   // degrees
        var lightness: Float = 0 // additive on luma-ish value, −0.1…0.1
    }

    // Monochrome channel mixes. Filter variants emulate the effect of a coloured lens filter
    // (yellow/red darken blue sky; green lightens foliage) — standard B&W practice, not Fuji data.
    private static let lumaMix = SIMD3<Float>(0.2126, 0.7152, 0.0722)
    private static let yeMix = SIMD3<Float>(0.32, 0.62, 0.06)
    private static let rMix = SIMD3<Float>(0.55, 0.40, 0.05)
    private static let gMix = SIMD3<Float>(0.18, 0.74, 0.08)

    static func profile(for sim: FilmSimulation) -> FilmLookProfile {
        switch sim {
        case .provia:
            return .init(contrast: 0.12, saturation: 1.05)
        case .velvia:
            return .init(contrast: 0.28, saturation: 1.38, highlightRolloff: 0.03,
                         hueBands: [.init(center: 120, width: 50, saturation: 1.15, hueShift: -4),
                                    .init(center: 220, width: 40, saturation: 1.15, hueShift: 4, lightness: -0.03)])
        case .astia:
            return .init(contrast: 0.05, saturation: 1.1, highlightRolloff: 0.1,
                         hueBands: [.init(center: 25, width: 30, saturation: 0.92, hueShift: 2, lightness: 0.02)])
        case .classicChrome:
            return .init(contrast: 0.2, saturation: 0.72, blackLift: 0.01,
                         shadowTint: [0.0, 0.006, 0.01], highlightTint: [0.012, 0.006, -0.008],
                         hueBands: [.init(center: 210, width: 45, saturation: 0.85, hueShift: -10, lightness: -0.04),
                                    .init(center: 0, width: 30, saturation: 0.8, hueShift: 4),
                                    .init(center: 110, width: 45, saturation: 0.75, hueShift: -8)])
        case .realaAce:
            return .init(contrast: 0.16, saturation: 1.08, highlightRolloff: 0.06,
                         hueBands: [.init(center: 30, width: 25, saturation: 1.0, hueShift: 0, lightness: 0.01)])
        case .proNegHi:
            return .init(contrast: 0.14, saturation: 0.96, highlightRolloff: 0.08,
                         hueBands: [.init(center: 25, width: 30, saturation: 0.94, hueShift: 1, lightness: 0.015)])
        case .proNegStd:
            return .init(contrast: -0.05, saturation: 0.88, highlightRolloff: 0.12,
                         hueBands: [.init(center: 25, width: 30, saturation: 0.92, hueShift: 1, lightness: 0.02)])
        case .classicNeg:
            return .init(contrast: 0.26, saturation: 0.9, blackLift: 0.02, highlightRolloff: 0.08,
                         shadowTint: [-0.01, 0.012, 0.02], highlightTint: [0.025, 0.01, -0.02],
                         hueBands: [.init(center: 110, width: 50, saturation: 0.85, hueShift: 18),
                                    .init(center: 0, width: 25, saturation: 1.05, hueShift: -6, lightness: -0.02),
                                    .init(center: 200, width: 40, saturation: 0.9, hueShift: 8)])
        case .nostalgicNeg:
            return .init(contrast: 0.1, saturation: 0.98, blackLift: 0.015, highlightRolloff: 0.14,
                         shadowTint: [0.005, 0.0, -0.005], highlightTint: [0.035, 0.018, -0.03],
                         hueBands: [.init(center: 40, width: 35, saturation: 1.12, hueShift: -3)])
        case .eterna:
            return .init(contrast: -0.12, saturation: 0.7, blackLift: 0.025, highlightRolloff: 0.18,
                         shadowTint: [-0.004, 0.006, 0.01],
                         hueBands: [.init(center: 180, width: 60, saturation: 0.95, hueShift: -6)])
        case .eternaBleachBypass:
            return .init(contrast: 0.38, saturation: 0.32, blackLift: 0.01, highlightRolloff: 0.04,
                         shadowTint: [0.0, 0.004, 0.006], highlightTint: [0.008, 0.008, 0.004])
        case .acros:
            return .init(contrast: 0.24, saturation: 0, highlightRolloff: 0.08, monoMix: lumaMix)
        case .acrosYe:
            return .init(contrast: 0.26, saturation: 0, highlightRolloff: 0.08, monoMix: yeMix)
        case .acrosR:
            return .init(contrast: 0.3, saturation: 0, highlightRolloff: 0.08, monoMix: rMix)
        case .acrosG:
            return .init(contrast: 0.24, saturation: 0, highlightRolloff: 0.08, monoMix: gMix)
        case .monochrome:
            return .init(contrast: 0.1, saturation: 0, monoMix: lumaMix)
        case .monochromeYe:
            return .init(contrast: 0.12, saturation: 0, monoMix: yeMix)
        case .monochromeR:
            return .init(contrast: 0.16, saturation: 0, monoMix: rMix)
        case .monochromeG:
            return .init(contrast: 0.1, saturation: 0, monoMix: gMix)
        case .sepia:
            return .init(contrast: 0.06, saturation: 0, blackLift: 0.01, monoMix: lumaMix, monoTone: [0.09, 0.03, -0.07])
        }
    }
}

/// Inputs that affect the 3D LUT. Kept small so cubes can be cached.
struct FilmLUTKey: Hashable, Sendable {
    var simulation: FilmSimulation
    var highlight: Float      // −2…+4
    var shadow: Float         // −2…+4
    var color: Float          // −4…+4
    var colorChrome: EffectLevel
    var colorChromeFXBlue: EffectLevel
    var monoWarmCool: Float   // −18…+18
    var monoMagentaGreen: Float
    /// 0 = none, 1 = DR200-like, 2 = DR400-like highlight protection.
    var highlightProtection: Float
    /// 0…1 extra shadow lift from D RANGE PRIORITY.
    var shadowProtection: Float

    init(settings s: RecipeSettings) {
        simulation = s.filmSimulation
        let manual = s.isToneAndDRManual
        highlight = Float(manual ? s.highlight.value(or: 0) : 0)
        shadow = Float(manual ? s.shadow.value(or: 0) : 0)
        color = Float(s.color.value(or: 0))
        colorChrome = s.colorChrome.value(or: .off)
        colorChromeFXBlue = s.colorChromeFXBlue.value(or: .off)
        monoWarmCool = Float(s.monochromaticWarmCool.value(or: 0))
        monoMagentaGreen = Float(s.monochromaticMagentaGreen.value(or: 0))
        switch (manual, s.dynamicRange.value(or: .dr100), s.dRangePriority.value(or: .off)) {
        case (false, _, .strong): highlightProtection = 2; shadowProtection = 0.8
        case (false, _, .weak): highlightProtection = 1; shadowProtection = 0.4
        case (false, _, _): highlightProtection = 1.5; shadowProtection = 0.6 // AUTO
        case (true, .dr400, _): highlightProtection = 2; shadowProtection = 0
        case (true, .dr200, _): highlightProtection = 1; shadowProtection = 0
        case (true, .auto, _): highlightProtection = 0.5; shadowProtection = 0
        default: highlightProtection = 0; shadowProtection = 0
        }
    }
}

/// Builds display-referred (sRGB-encoded) 3D LUTs. Pure functions → unit-testable.
enum FilmLUTBuilder {
    static let dimension = 25

    /// Transforms one sRGB-encoded colour (0…1 per channel).
    static func transform(_ input: SIMD3<Float>, key: FilmLUTKey) -> SIMD3<Float> {
        let p = FilmLookProfile.profile(for: key.simulation)
        var c = simd_clamp(input, .zero, .one)

        // 1. Tone: highlight/shadow tone curve (+ = harder), DR highlight protection.
        c = applyTone(c, key: key, profile: p)

        if let mix = p.monoMix {
            // 2a. Monochrome: channel mix, contrast, WC/MG toning.
            var y = simd_dot(c, mix)
            y = sCurve(y, p.contrast)
            y = rolloff(y, p.highlightRolloff)
            if key.colorChrome != .off {
                // Colour chrome deepens tonality on saturated subjects in B&W as well.
                let chroma = chromaOf(input)
                y -= chroma * (key.colorChrome == .strong ? 0.08 : 0.04) * y
            }
            var out = SIMD3<Float>(repeating: y)
            let mid = 4 * y * (1 - y) // strongest in midtones
            out += p.monoTone * mid
            let wc = key.monoWarmCool / 18, mg = key.monoMagentaGreen / 18
            out += SIMD3<Float>(wc * 0.06, 0, -wc * 0.06) * mid
            out += SIMD3<Float>(mg * 0.03, -mg * 0.05, mg * 0.03) * mid
            out = SIMD3<Float>(repeating: p.blackLift) + out * (1 - p.blackLift)
            return simd_clamp(out, .zero, .one)
        }

        // 2b. Colour: hue bands, global saturation (+ COLOR setting), chrome effects.
        var hsv = rgbToHSV(c)
        var bandSat: Float = 1
        var bandLight: Float = 0
        for band in p.hueBands {
            let w = bandWeight(hue: hsv.x, center: band.center, width: band.width)
            guard w > 0 else { continue }
            hsv.x += band.hueShift * w
            bandSat *= 1 + (band.saturation - 1) * w
            bandLight += band.lightness * w * hsv.y
        }
        let colorSetting = 1 + key.color * 0.09
        hsv.y = min(hsv.y * p.saturation * bandSat * colorSetting, 1)
        hsv.x = fmodf(hsv.x + 360, 360)
        c = hsvToRGB(hsv)
        c += SIMD3<Float>(repeating: bandLight)

        // Colour chrome: darkens/deepens highly saturated colours.
        if key.colorChrome != .off {
            let chroma = chromaOf(c)
            let amount: Float = key.colorChrome == .strong ? 0.16 : 0.08
            c *= 1 - amount * chroma * chroma
        }
        // Colour chrome FX Blue: deepens blues specifically.
        if key.colorChromeFXBlue != .off {
            let w = bandWeight(hue: hsv.x, center: 220, width: 40) * hsv.y
            let amount: Float = key.colorChromeFXBlue == .strong ? 0.2 : 0.1
            c *= 1 - amount * w
            c.z += amount * 0.25 * w
        }

        // 3. Film contrast and roll-off, per channel (keeps slight hue shifts natural).
        c = SIMD3(sCurve(c.x, p.contrast), sCurve(c.y, p.contrast), sCurve(c.z, p.contrast))
        c = SIMD3(rolloff(c.x, p.highlightRolloff), rolloff(c.y, p.highlightRolloff), rolloff(c.z, p.highlightRolloff))

        // 4. Split toning and fade.
        let y = simd_dot(c, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        c += p.shadowTint * (1 - y) * (1 - y)
        c += p.highlightTint * y * y
        c = SIMD3<Float>(repeating: p.blackLift) + c * (1 - p.blackLift)
        return simd_clamp(c, .zero, .one)
    }

    static func applyTone(_ c: SIMD3<Float>, key: FilmLUTKey, profile: FilmLookProfile) -> SIMD3<Float> {
        func curve(_ x: Float) -> Float {
            var v = x
            // Shadow: + darkens shadows (harder), − lifts them. Weighted to lower half.
            let sw = max(0, 1 - v * 2)
            v -= key.shadow * 0.035 * sw * sw * 4 * v
            v += key.shadowProtection * 0.06 * sw
            // Highlight: + brightens highlights (harder), − compresses them.
            let hw = max(0, v * 2 - 1)
            v += key.highlight * 0.03 * hw * hw * 4 * (1 - v)
            // DR protection: soft-knee compression of the top end.
            if key.highlightProtection > 0 { v = rolloff(v, 0.12 * key.highlightProtection) }
            return min(max(v, 0), 1)
        }
        return SIMD3(curve(c.x), curve(c.y), curve(c.z))
    }

    /// Generates RGBA float32 cube data for `CIColorCubeWithColorSpace` (red varies fastest).
    static func cubeData(for key: FilmLUTKey, dimension n: Int = dimension) -> Data {
        var floats = [Float](repeating: 0, count: n * n * n * 4)
        let scale = 1 / Float(n - 1)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = transform(SIMD3(Float(r) * scale, Float(g) * scale, Float(b) * scale), key: key)
                    floats[i] = out.x; floats[i + 1] = out.y; floats[i + 2] = out.z; floats[i + 3] = 1
                    i += 4
                }
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: helpers

    static func sCurve(_ x: Float, _ k: Float) -> Float {
        let s = x * x * (3 - 2 * x) // smoothstep
        return k >= 0 ? x + (s - x) * min(k * 2.2, 1) : x + (0.5 + (x - 0.5) * 0.7 - x) * min(-k * 2.2, 1)
    }

    static func rolloff(_ x: Float, _ amount: Float) -> Float {
        guard amount > 0 else { return x }
        let knee = 1 - amount
        guard x > knee else { return x }
        // Shoulder with slope 1 at the knee and monotonic up to 1: white maps to
        // knee + 0.65·amount, i.e. gently compressed highlights.
        let t = (x - knee) / amount
        return knee + amount * (t - 0.35 * t * t)
    }

    static func chromaOf(_ c: SIMD3<Float>) -> Float { (c.max() - c.min()) }

    static func bandWeight(hue: Float, center: Float, width: Float) -> Float {
        var d = abs(hue - center).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        guard d < width else { return 0 }
        let t = 1 - d / width
        return t * t * (3 - 2 * t)
    }

    static func rgbToHSV(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let mx = c.max(), mn = c.min(), d = mx - mn
        var h: Float = 0
        if d > 1e-6 {
            if mx == c.x { h = 60 * fmodf((c.y - c.z) / d, 6) }
            else if mx == c.y { h = 60 * ((c.z - c.x) / d + 2) }
            else { h = 60 * ((c.x - c.y) / d + 4) }
        }
        if h < 0 { h += 360 }
        return SIMD3(h, mx > 0 ? d / mx : 0, mx)
    }

    static func hsvToRGB(_ hsv: SIMD3<Float>) -> SIMD3<Float> {
        let h = fmodf(hsv.x, 360) / 60, s = hsv.y, v = hsv.z
        let c = v * s, x = c * (1 - abs(fmodf(h, 2) - 1)), m = v - c
        let rgb: SIMD3<Float>
        switch Int(h) {
        case 0: rgb = [c, x, 0]
        case 1: rgb = [x, c, 0]
        case 2: rgb = [0, c, x]
        case 3: rgb = [0, x, c]
        case 4: rgb = [x, 0, c]
        default: rgb = [c, 0, x]
        }
        return rgb + SIMD3(repeating: m)
    }
}
