import Foundation
import CoreGraphics
import Vision

/// One recognized line of text. `box` is normalized (0…1) with a TOP-LEFT origin, y down.
struct OCRTextBlock: Equatable, Sendable, Codable {
    var text: String
    var box: CGRect
    var confidence: Float

    var midX: CGFloat { box.midX }
    var midY: CGFloat { box.midY }
}

enum RecipeOCRError: Error, LocalizedError {
    case noText
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noText: "No text was found in this image. Try a sharper screenshot of the recipe card."
        case .failed(let m): "Text recognition failed: \(m)"
        }
    }
}

/// On-device text recognition with Apple's Vision framework. Nothing leaves the device.
enum RecipeCardOCR {
    static func recognize(_ image: CGImage, fast: Bool = false) async throws -> [OCRTextBlock] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = fast ? .fast : .accurate
            request.minimumTextHeight = 0
            // Language correction "fixes" values like "-0.5" or "DR400"; keep the raw text.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { throw RecipeOCRError.failed(error.localizedDescription) }
            let blocks: [OCRTextBlock] = (request.results ?? []).compactMap { obs in
                guard let top = obs.topCandidates(1).first else { return nil }
                let b = obs.boundingBox // normalized, bottom-left origin
                return OCRTextBlock(text: top.string,
                                    box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height),
                                    confidence: top.confidence)
            }
            guard !blocks.isEmpty else { throw RecipeOCRError.noText }
            return blocks
        }.value
    }
}

/// Full pipeline: OCR → parse → targeted re-OCR of any value the first pass missed
/// (single digits like "0" are often skipped at card scale; a 3× crop fixes most of them).
enum RecipeImageImporter {
    static func importRecipe(from image: CGImage) async throws -> RecipeImportDraft {
        let blocks = try await RecipeCardOCR.recognize(image)
        var draft = RecipeCardParser.parse(blocks: blocks)
        if !draft.isUsable {
            // Not a card layout? Try reading it as "Key: Value" text.
            let text = blocks.sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }.map(\.text).joined(separator: "\n")
            let asText = RecipeCardParser.parse(text: text)
            if asText.isUsable { draft = asText }
        }
        for (key, region) in draft.missing {
            guard let crop = crop(image, normalized: region, upscale: 4) else { continue }
            // Vision sometimes skips a lone glyph like "0" at card scale; one enlarged retry.
            // Anything still unread stays `.unset` and is flagged for the user — never guessed.
            guard let retry = try? await RecipeCardOCR.recognize(crop) else { continue }
            for block in retry.sorted(by: { $0.box.height > $1.box.height }) where draft.missing[key] != nil {
                RecipeCardParser.fill(key, from: block.text, into: &draft)
            }
        }
        return draft
    }

    /// Crops a normalized top-left rect and scales it up (Vision reads small glyphs better).
    static func crop(_ image: CGImage, normalized r: CGRect, upscale: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h).integral
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty, let cropped = image.cropping(to: rect) else { return nil }
        let ow = Int(rect.width * upscale), oh = Int(rect.height * upscale)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: ow, height: oh))
        return ctx.makeImage()
    }
}
