import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Builds the approximate on-device Core Image graph for a recipe.
///
/// Transform order (documented contract, see docs/architecture.md › Offline pipeline):
///  1. decode & normalize   — caller supplies an oriented, colour-managed `CIImage`
///  2. exposure / WB        — suggested EV, Kelvin/preset temperature, R/B shift (linear light)
///  3. tone / contrast      ┐
///  4. base film profile    │ one cached 3D LUT in sRGB-encoded space (FilmLUTBuilder)
///  5. saturation / chrome  │
///  6. monochrome           ┘
///  7. clarity / detail / NR — size-relative spatial filters
///  8. grain                — deterministic, size-relative noise
///  9. output conversion    — performed by the renderer's CIContext into an explicit colour space
///
/// Always rendered from the untouched source image, so edits never accumulate.
final class FilmLookEngine: @unchecked Sendable {
    // @unchecked Sendable justification: the only mutable state is `lutCache`, which is guarded
    // by `lock`. All other members are immutable after init.
    static let version = "filmlab-approx-1"

    private let lock = NSLock()
    private var lutCache: [FilmLUTKey: Data] = [:]
    private var lutOrder: [FilmLUTKey] = []
    private let lutCacheLimit = 48
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    func cube(for key: FilmLUTKey) -> Data {
        lock.lock()
        if let hit = lutCache[key] {
            lutOrder.removeAll { $0 == key }
            lutOrder.append(key)
            lock.unlock()
            return hit
        }
        lock.unlock()
        let data = FilmLUTBuilder.cubeData(for: key)
        lock.lock()
        lutCache[key] = data
        lutOrder.append(key)
        if lutOrder.count > lutCacheLimit { lutCache.removeValue(forKey: lutOrder.removeFirst()) }
        lock.unlock()
        return data
    }

    /// - Parameter source: oriented working image (already downsampled for previews).
    func apply(_ settings: RecipeSettings, to source: CIImage) -> CIImage {
        let s = settings.normalized()
        let extent = source.extent
        let shortSide = max(1, min(extent.width, extent.height))
        var image = source

        // 2. Exposure & white balance (CI working space is linear).
        let ev = s.suggestedExposureCompensation.value(or: 0)
        if ev != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(ev)
            image = f.outputImage ?? image
        }
        if let kelvin = Self.previewKelvin(s) {
            // The source is assumed to be rendered for ~5500 K daylight. Setting a higher WB
            // Kelvin on camera renders warmer; lower renders cooler.
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: CGFloat(kelvin), y: 0)
            f.targetNeutral = CIVector(x: 5500, y: 0)
            image = f.outputImage ?? image
        }
        let red = Double(s.wbShiftRed.value(or: 0)), blue = Double(s.wbShiftBlue.value(or: 0))
        if red != 0 || blue != 0 {
            let f = CIFilter.colorMatrix()
            f.inputImage = image
            f.rVector = CIVector(x: 1 + red * 0.025, y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: 1 - (red + blue) * 0.004, z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: 1 + blue * 0.025, w: 0)
            image = f.outputImage ?? image
        }

        // 3–6. Film look LUT (sRGB-encoded domain).
        let cubeFilter = CIFilter.colorCubeWithColorSpace()
        cubeFilter.inputImage = image
        cubeFilter.cubeDimension = Float(FilmLUTBuilder.dimension)
        cubeFilter.cubeData = cube(for: FilmLUTKey(settings: s))
        cubeFilter.colorSpace = srgb
        image = cubeFilter.outputImage ?? image

        // 7. Clarity (large-radius local contrast), sharpness, noise reduction.
        let clarity = Float(s.clarity.value(or: 0))
        if clarity != 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image
            f.radius = Float(shortSide * 0.02)
            f.intensity = clarity * 0.09
            image = f.outputImage ?? image
        }
        let sharp = Float(s.sharpness.value(or: 0))
        if sharp > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = sharp * 0.12
            f.radius = Float(max(1, shortSide / 1500))
            image = f.outputImage ?? image
        } else if sharp < 0 {
            let f = CIFilter.gaussianBlur()
            f.inputImage = image.clampedToExtent()
            f.radius = Float(-sharp) * Float(max(0.25, shortSide / 6000))
            image = (f.outputImage ?? image).cropped(to: extent)
        }
        let nr = Float(s.highISONR.value(or: 0))
        if nr > 0 {
            let f = CIFilter.noiseReduction()
            f.inputImage = image
            f.noiseLevel = nr * 0.006
            f.sharpness = 0.4
            image = f.outputImage ?? image
        }

        // 8. Grain.
        if let rough = s.grainRoughness.concreteValue, rough != .off {
            image = Self.addGrain(to: image, roughness: rough, size: s.grainSize.value(or: .small), shortSide: shortSide)
        }
        return image.cropped(to: extent)
    }

    static func previewKelvin(_ s: RecipeSettings) -> Double? {
        guard let wb = s.whiteBalance.concreteValue else { return nil }
        if wb == .colorTemperature { return s.kelvin.concreteValue.map(Double.init) }
        return wb.approximatePreviewKelvin
    }

    /// Deterministic monochrome grain whose size scales with the output so a thumbnail and an
    /// export look alike. Multiplicative in linear light (pixel × (1 + n)), so every channel
    /// changes by the same ratio: luminance-only grain with no colour sparkle, mean preserved.
    static func addGrain(to image: CIImage, roughness: GrainRoughness, size: GrainSize, shortSide: CGFloat) -> CIImage {
        let extent = image.extent
        let grainPixels = max(1, shortSide / 1400) * (size == .large ? 2.2 : 1.1)
        let amplitude: CGFloat = roughness == .strong ? 0.34 : 0.2
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        // factor = 1 + (n − 0.5)·amplitude in every channel, alpha = 1.
        // The noise source is the generator's ALPHA channel: CIColorMatrix un-premultiplies its
        // input (rgb ÷ alpha), and the generator's alpha is itself random, so its rgb channels
        // would explode near alpha = 0. Alpha is unaffected by un-premultiplying.
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        let a = amplitude
        mono.rVector = CIVector(x: 0, y: 0, z: 0, w: a)
        mono.gVector = CIVector(x: 0, y: 0, z: 0, w: a)
        mono.bVector = CIVector(x: 0, y: 0, z: 0, w: a)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 1 - a / 2, y: 1 - a / 2, z: 1 - a / 2, w: 1)
        guard let factor = mono.outputImage else { return image }
        let scaled = factor
            .transformed(by: CGAffineTransform(scaleX: grainPixels, y: grainPixels))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        // Soften slightly so scaled grain isn't blocky.
        let soft = scaled.applyingGaussianBlur(sigma: Double(grainPixels) * 0.3).cropped(to: extent)
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = soft
        multiply.backgroundImage = image
        return multiply.outputImage?.cropped(to: extent) ?? image
    }
}
