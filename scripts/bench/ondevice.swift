// On-device baseline: Apple Vision OCR + FilmLab's deterministic parser on the benchmark fixtures.
// Outputs ExtractedRecipe-shaped JSON (same field names) so web/bench can score it.
import Foundation
import ImageIO

@main struct OnDeviceBench {
    static func main() async throws {
        let dirs = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
        var out: [String: Any] = [:]
        for dir in dirs {
            for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                where ["png", "jpg"].contains(file.pathExtension) {
                let src = CGImageSourceCreateWithURL(file as CFURL, nil)!
                let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
                let start = Date()
                let d = (try? await RecipeImageImporter.importRecipe(from: img)) ?? RecipeImportDraft()
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let s = d.settings.normalized()
                func v<T>(_ f: RecipeField<T>) -> Any { f.concreteValue.map { $0 as Any } ?? NSNull() }
                func e<T: RawRepresentable>(_ f: RecipeField<T>) -> Any { f.concreteValue.map { $0.rawValue as Any } ?? NSNull() }
                // Report raw values (before dependency rules), like the AI path does.
                let r = d.settings
                out[file.deletingPathExtension().lastPathComponent] = [
                    "latencyMs": ms, "usable": d.isUsable,
                    "output": [
                        "name": d.name, "filmSimulation": d.isUsable ? s.filmSimulation.rawValue : NSNull(),
                        "grainRoughness": e(r.grainRoughness), "grainSize": e(r.grainSize), "colorChrome": e(r.colorChrome),
                        "colorChromeFXBlue": e(r.colorChromeFXBlue), "whiteBalance": e(r.whiteBalance), "kelvin": v(r.kelvin),
                        "wbShiftRed": v(r.wbShiftRed), "wbShiftBlue": v(r.wbShiftBlue), "dynamicRange": e(r.dynamicRange),
                        "dRangePriority": e(r.dRangePriority), "highlight": v(r.highlight), "shadow": v(r.shadow), "color": v(r.color),
                        "sharpness": v(r.sharpness), "highISONR": v(r.highISONR), "clarity": v(r.clarity),
                        "monochromaticWarmCool": v(r.monochromaticWarmCool), "monochromaticMagentaGreen": v(r.monochromaticMagentaGreen),
                        "exposureCompensation": v(r.suggestedExposureCompensation), "otherSettings": d.otherSettings.map { ["label": $0.label, "value": $0.value] },
                    ] as [String: Any],
                ]
            }
        }
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("wrote \(out.count) results")
    }
}
