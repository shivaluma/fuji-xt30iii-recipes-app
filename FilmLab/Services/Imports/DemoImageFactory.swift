import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Generates ORIGINAL synthetic test images at runtime, so the app ships no third-party
/// photos. They contain sky gradients, foliage, skin-tone and saturated patches and a grey
/// ramp — enough to see how each look treats colour, contrast and highlights.
enum DemoImageFactory {
    struct Scene: Sendable {
        var name: String
        var draw: @Sendable (CGContext, CGSize) -> Void
    }

    static let scenes: [Scene] = [
        Scene(name: "Synthetic Landscape", draw: drawLandscape),
        Scene(name: "Synthetic Colour Chart", draw: drawChart),
    ]

    static func jpegData(for scene: Scene, size: CGSize = CGSize(width: 1800, height: 1200)) -> Data? {
        let w = Int(size.width), h = Int(size.height)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        scene.draw(ctx, size)
        guard let image = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) else { return }
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    @Sendable static func drawLandscape(_ ctx: CGContext, _ size: CGSize) {
        let w = size.width, h = size.height
        // Sky (CG origin is bottom-left).
        gradient(ctx, [rgb(0.98, 0.78, 0.55), rgb(0.55, 0.72, 0.92), rgb(0.18, 0.38, 0.75)],
                 from: CGPoint(x: 0, y: h * 0.45), to: CGPoint(x: 0, y: h))
        // Sun with a soft bright halo (tests highlight roll-off).
        if let halo = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [rgb(1, 1, 0.94), rgb(1, 0.9, 0.65), rgb(1, 0.85, 0.6).copy(alpha: 0)!] as CFArray,
                                 locations: [0, 0.25, 1]) {
            ctx.drawRadialGradient(halo, startCenter: CGPoint(x: w * 0.72, y: h * 0.62), startRadius: 0,
                                   endCenter: CGPoint(x: w * 0.72, y: h * 0.62), endRadius: h * 0.35, options: [])
        }
        // Far hills, near hills, field.
        func hill(_ base: CGFloat, _ amp: CGFloat, _ freq: CGFloat, _ color: CGColor) {
            ctx.setFillColor(color)
            ctx.move(to: CGPoint(x: 0, y: 0))
            stride(from: 0, through: w, by: 8).forEach { x in
                ctx.addLine(to: CGPoint(x: x, y: h * base + sin(x / w * .pi * freq) * h * amp))
            }
            ctx.addLine(to: CGPoint(x: w, y: 0)); ctx.closePath(); ctx.fillPath()
        }
        hill(0.48, 0.05, 3, rgb(0.42, 0.52, 0.62))
        hill(0.40, 0.06, 2.2, rgb(0.22, 0.42, 0.24))
        hill(0.26, 0.03, 4, rgb(0.36, 0.56, 0.18))
        // Red barn + white wall (saturated red + near-white).
        ctx.setFillColor(rgb(0.72, 0.12, 0.1)); ctx.fill(CGRect(x: w * 0.18, y: h * 0.2, width: w * 0.12, height: h * 0.12))
        ctx.setFillColor(rgb(0.95, 0.94, 0.9)); ctx.fill(CGRect(x: w * 0.3, y: h * 0.2, width: w * 0.05, height: h * 0.1))
        // Foreground skin-tone and denim swatches (portrait-ish tones).
        let swatches: [CGColor] = [rgb(0.94, 0.78, 0.66), rgb(0.82, 0.6, 0.47), rgb(0.55, 0.37, 0.27), rgb(0.2, 0.3, 0.5), rgb(0.95, 0.85, 0.2)]
        for (i, c) in swatches.enumerated() {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: w * (0.5 + CGFloat(i) * 0.09), y: h * 0.05, width: w * 0.07, height: w * 0.07))
        }
        // Shadow band.
        ctx.setFillColor(rgb(0.04, 0.05, 0.05)); ctx.fill(CGRect(x: 0, y: 0, width: w * 0.12, height: h * 0.18))
    }

    @Sendable static func drawChart(_ ctx: CGContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.setFillColor(rgb(0.2, 0.2, 0.2)); ctx.fill(CGRect(origin: .zero, size: size))
        // 6×4 patches of original colour choices spanning hues, skin and neutrals.
        let colors: [[CGFloat]] = [
            [0.45, 0.32, 0.26], [0.77, 0.58, 0.5], [0.36, 0.48, 0.61], [0.35, 0.42, 0.25], [0.51, 0.5, 0.69], [0.4, 0.74, 0.67],
            [0.86, 0.48, 0.18], [0.29, 0.36, 0.65], [0.76, 0.33, 0.38], [0.36, 0.24, 0.42], [0.62, 0.74, 0.25], [0.89, 0.63, 0.18],
            [0.17, 0.24, 0.58], [0.27, 0.58, 0.29], [0.69, 0.19, 0.22], [0.93, 0.78, 0.13], [0.73, 0.33, 0.58], [0.0, 0.52, 0.64],
            [0.95, 0.95, 0.94], [0.78, 0.78, 0.78], [0.63, 0.63, 0.63], [0.47, 0.47, 0.47], [0.33, 0.33, 0.33], [0.2, 0.2, 0.2],
        ]
        let cols = 6, rows = 4
        let pad = w * 0.02
        let cw = (w - pad * CGFloat(cols + 1)) / CGFloat(cols)
        let ch = (h * 0.75 - pad * CGFloat(rows + 1)) / CGFloat(rows)
        for (i, c) in colors.enumerated() {
            let col = i % cols, row = rows - 1 - i / cols
            ctx.setFillColor(rgb(c[0], c[1], c[2]))
            ctx.fill(CGRect(x: pad + CGFloat(col) * (cw + pad), y: h * 0.25 + pad + CGFloat(row) * (ch + pad), width: cw, height: ch))
        }
        // Grey ramp and rainbow ramp along the bottom.
        gradient(ctx, [rgb(0, 0, 0), rgb(1, 1, 1)], from: CGPoint(x: pad, y: 0), to: CGPoint(x: w - pad, y: 0))
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: h * 0.13, width: w, height: h * 0.1))
        gradient(ctx, [rgb(1, 0, 0), rgb(1, 1, 0), rgb(0, 1, 0), rgb(0, 1, 1), rgb(0, 0, 1), rgb(1, 0, 1), rgb(1, 0, 0)],
                 from: CGPoint(x: 0, y: 0), to: CGPoint(x: w, y: 0))
        ctx.restoreGState()
        ctx.setFillColor(rgb(0.2, 0.2, 0.2)); ctx.fill(CGRect(x: 0, y: h * 0.11, width: w, height: h * 0.02))
        ctx.fill(CGRect(x: 0, y: h * 0.23, width: w, height: h * 0.02))
    }
}
