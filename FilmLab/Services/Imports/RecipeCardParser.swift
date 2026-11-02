import Foundation
import CoreGraphics

/// Result of reading a recipe from an image or text. Everything is a *suggestion* the user
/// reviews before saving; fields that weren't read stay `.unset` and are listed in `missing`.
struct RecipeImportDraft: Sendable {
    var name: String = ""
    /// Camera the card says it was made for, e.g. "X-T30 III".
    var cameraModel: String?
    /// Credit printed on the card (often the photographer's handle).
    var credit: String?
    /// App/brand footer seen on the card, kept only as a provenance note.
    var sourceNote: String?
    var settings = RecipeSettings(filmSimulation: .provia)
    var filmSimulationFound = false
    /// Properties read with a concrete value (or an explicit "-"/Off).
    var found: Set<RecipePropertyKey> = []
    /// Labels we saw but whose value we couldn't read; with the value region for an OCR retry.
    var missing: [RecipePropertyKey: CGRect] = [:]
    /// Properties the reader (e.g. the AI) flagged as hard to read; shown for double-checking.
    var uncertain: Set<RecipePropertyKey> = []
    /// Things on the card FilmLab doesn't store as recipe settings (e.g. "ISO: Auto").
    var notes: [String] = []
    var unrecognized: [String] = []
    /// Validation/compatibility messages from the AI path (server-side checks).
    var reviewMessages: [(isError: Bool, text: String)] = []
    /// On-device result is incomplete: unusable, or fields seen but not read. Used to decide AI fallback.
    var needsAIFallback: Bool { !isUsable || !missing.isEmpty }
    /// "Label: value" settings that don't map to a FilmLab field (e.g. "Smooth Skin Effect: Strong").
    var otherSettings: [(label: String, value: String)] = []

    /// Settings the X-T30 III doesn't have (kept, never applied).
    var unsupportedWarnings: [String] {
        otherSettings.compactMap { o in
            o.label.lowercased().contains("smooth skin")
                ? "Smooth Skin Effect (\(o.value)) isn't available on the X-T30 III — it has Portrait Enhancer instead." : nil
        }
    }

    var isUsable: Bool { filmSimulationFound }

    func recipe(now: Date = Date()) -> FilmRecipe {
        var note = "Imported from a recipe image"
        if let sourceNote { note += " (\(sourceNote))" }
        if let cameraModel { note += ". Card made for \(cameraModel)." }
        let cameras = [CameraProfile.xt30III.modelName] + (cameraModel.map { $0 == CameraProfile.xt30III.modelName ? [] : [$0] } ?? [])
        return FilmRecipe(
            name: name.isEmpty ? "Imported Recipe" : name,
            summary: notes.joined(separator: " · "),
            settings: settings.normalized(),
            tags: [],
            compatibleCameras: cameras,
            provenance: RecipeProvenance(kind: .imported, author: credit, note: note),
            createdAt: now, updatedAt: now)
    }
}

/// Parses recipe cards (spatial OCR layout: value above its label) and plain-text recipes
/// ("Film Simulation: Classic Chrome" lines). Pure and unit-tested.
enum RecipeCardParser {

    // MARK: Labels

    enum Field: Hashable {
        case property(RecipePropertyKey)
        case grain          // roughness (and size when combined, e.g. "Weak, Small")
        case wbShift        // "Red: +1 Blue: -1"
        case exposure
        case iso
        case monochromatic  // "WC +2 MG -1"
    }

    /// Normalized label → field. Normalization: lowercase, letters/digits only.
    static let labels: [String: Field] = {
        var m: [String: Field] = [:]
        func add(_ f: Field, _ names: String...) { for n in names { m[normalize(n)] = f } }
        add(.property(.filmSimulation), "film simulation", "film simulations", "film sim", "simulation", "base", "mô phỏng phim", "giả lập phim")
        add(.grain, "grain effect", "grain", "grain roughness", "grain effect roughness", "hạt", "hiệu ứng hạt")
        add(.property(.grainSize), "grain size", "grain effect size")
        add(.property(.colorChrome), "color effect", "color chrome effect", "color chrome", "colour chrome effect", "cc effect")
        add(.property(.colorChromeFXBlue), "color fx blue", "color chrome fx blue", "colour chrome fx blue", "fx blue", "cc fx blue", "cce blue")
        add(.property(.whiteBalance), "white balance", "wb", "cân bằng trắng")
        add(.wbShift, "wb shift", "white balance shift")
        add(.property(.dynamicRange), "dynamic range", "dr", "dải tương phản động", "dải động")
        add(.property(.dRangePriority), "d range priority", "dr priority", "drange priority")
        add(.property(.highlight), "highlight", "highlights", "highlight tone", "tone curve highlight", "vùng sáng")
        add(.property(.shadow), "shadow", "shadows", "shadow tone", "tone curve shadow", "vùng tối")
        add(.property(.color), "color", "colour", "saturation", "màu", "màu sắc")
        add(.property(.sharpness), "sharpness", "sharpening", "độ nét")
        add(.property(.highISONR), "iso denoise", "noise reduction", "high iso nr", "high iso noise reduction", "nr", "denoise", "giảm nhiễu")
        add(.property(.clarity), "clarity", "độ rõ", "độ trong")
        add(.monochromatic, "monochromatic color", "monochromatic colour", "mono color", "toning")
        add(.exposure, "exposure compensation", "exposure", "ev", "exposure comp")
        add(.iso, "iso")
        return m
    }()

    static func normalize(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// Branding/footer text that is never a value.
    static func isBoilerplate(_ s: String) -> Bool {
        let n = normalize(s)
        return n.hasPrefix("madewith") || n == "fuji" || n == "style" || n == "fujistyle" || n.hasPrefix("filmrecipe")
    }

    // MARK: Value parsers

    static func cleanNumberText(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "±", with: "")
        // OCR reads a lone zero as the letter O.
        if t == "O" || t == "o" || t == "+O" || t == "-O" { return "0" }
        return t.replacingOccurrences(of: " ", with: "")
    }

    /// "+1", "-0.5", "0", "O", "+1/3" (fractions for exposure). `nil` for "-" (not specified).
    static func number(_ s: String) -> Double? {
        let t = cleanNumberText(s)
        if t.isEmpty || t == "-" || t.lowercased() == "n/a" { return nil }
        if let r = t.range(of: #"^[+-]?\d+(\.\d+)?"#, options: .regularExpression) {
            let head = String(t[r])
            let rest = t[r.upperBound...]
            // Mixed/simple fractions: "+1/3", "-2/3", "+1 1/3"
            if rest.hasPrefix("/"), let den = Double(rest.dropFirst().prefix { $0.isNumber }), den > 0 {
                return (Double(head) ?? 0) / den
            }
            return Double(head)
        }
        return nil
    }

    static func filmSimulation(_ s: String) -> FilmSimulation? {
        var t = s.uppercased()
        for (a, b) in [(".", " "), ("/", " "), ("FILTER", ""), ("+", " + "), ("-", " ")] { t = t.replacingOccurrences(of: a, with: b) }
        let words = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let key = words.replacingOccurrences(of: " + ", with: "+")
        let table: [(String, FilmSimulation)] = [
            ("ETERNA BLEACH BYPASS", .eternaBleachBypass), ("BLEACH BYPASS", .eternaBleachBypass),
            ("NOSTALGIC NEG", .nostalgicNeg), ("CLASSIC NEG", .classicNeg), ("CLASSIC CHROME", .classicChrome),
            ("REALA ACE", .realaAce), ("REALA", .realaAce),
            ("PRO NEG HI", .proNegHi), ("PRO NEG STD", .proNegStd), ("PRO NEG STANDARD", .proNegStd),
            ("ACROS+YE", .acrosYe), ("ACROS+Y", .acrosYe), ("ACROS+R", .acrosR), ("ACROS+G", .acrosG), ("ACROS", .acros),
            ("MONOCHROME+YE", .monochromeYe), ("MONOCHROME+Y", .monochromeYe), ("MONOCHROME+R", .monochromeR),
            ("MONOCHROME+G", .monochromeG), ("MONOCHROME", .monochrome),
            ("ETERNA", .eterna), ("CINEMA", .eterna), ("SEPIA", .sepia),
            ("VELVIA", .velvia), ("VIVID", .velvia), ("ASTIA", .astia), ("SOFT", .astia),
            ("PROVIA", .provia), ("STANDARD", .provia),
        ]
        return table.first { key.contains($0.0) }?.1
    }

    static func whiteBalance(_ s: String) -> (WhiteBalanceMode, Int?)? {
        let t = s.uppercased().replacingOccurrences(of: ",", with: " ")
        if let r = t.range(of: #"(\d{4,5})\s*K"#, options: .regularExpression) {
            let digits = t[r].filter(\.isNumber)
            if let k = Int(digits) { return (.colorTemperature, k) }
        }
        let n = normalize(t)
        let table: [(String, WhiteBalanceMode)] = [
            ("whitepriority", .autoWhitePriority), ("ambiencepriority", .autoAmbiencePriority),
            ("custom1", .custom1), ("custom2", .custom2), ("custom3", .custom3),
            ("fluorescentlight1", .fluorescent1), ("fluorescent1", .fluorescent1),
            ("fluorescentlight2", .fluorescent2), ("fluorescent2", .fluorescent2),
            ("fluorescentlight3", .fluorescent3), ("fluorescent3", .fluorescent3),
            ("daylight", .daylight), ("fine", .daylight), ("shade", .shade), ("incandescent", .incandescent),
            ("underwater", .underwater), ("auto", .auto),
        ]
        return table.first { n.contains($0.0) }.map { ($0.1, nil) }
    }

    static func wbShift(_ s: String) -> (red: Int?, blue: Int?) {
        let t = cleanNumberText(s.replacingOccurrences(of: "&", with: " "))
        func grab(_ pattern: String) -> Int? {
            guard let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let m = String(t[r])
            guard let n = m.range(of: #"[+-]?\d+"#, options: .regularExpression) else { return nil }
            return Int(m[n])
        }
        // Two spellings: "Red:+1Blue:-1" (name first) and "+2Red-4Blue" (number first). In
        // "+2Red-4Blue" the name-first pattern would wrongly read "Red-4", so prefer the
        // number-first form whenever it matches for both colours.
        let postRed = grab(#"[+-]?\d+R(ed)?"#), postBlue = grab(#"[+-]?\d+B(lue)?"#)
        if postRed != nil, postBlue != nil { return (postRed, postBlue) }
        let red = grab(#"R(ed)?:?[+-]?\d+"#) ?? postRed
        let blue = grab(#"B(lue)?:?[+-]?\d+"#) ?? postBlue
        return (red, blue)
    }

    static func effect(_ s: String) -> EffectLevel? {
        switch normalize(s) {
        case "strong": .strong
        case "weak": .weak
        case "off": .off
        default: nil
        }
    }

    static func grain(_ s: String) -> (GrainRoughness?, GrainSize?) {
        let n = normalize(s)
        let rough: GrainRoughness? = n.contains("strong") ? .strong : n.contains("weak") ? .weak : n.contains("off") ? .off : nil
        let size: GrainSize? = n.contains("large") ? .large : n.contains("small") ? .small : nil
        return (rough, size)
    }

    static func dynamicRange(_ s: String) -> DynamicRangeSetting? {
        let n = normalize(s)
        if n.contains("400") { return .dr400 }
        if n.contains("200") { return .dr200 }
        if n.contains("100") { return .dr100 }
        if n.contains("auto") { return .auto }
        return nil
    }

    static func drPriority(_ s: String) -> DRangePriority? {
        let n = normalize(s)
        return n.contains("strong") ? .strong : n.contains("weak") ? .weak : n.contains("auto") ? .auto : n.contains("off") ? .off : nil
    }

    static func monochromatic(_ s: String) -> (wc: Int?, mg: Int?) {
        let t = cleanNumberText(s).uppercased()
        func grab(_ tag: String) -> Int? {
            guard let r = t.range(of: tag + #":?[+-]?\d+"#, options: .regularExpression),
                  let n = t[r].range(of: #"[+-]?\d+"#, options: .regularExpression) else { return nil }
            return Int(t[r][n])
        }
        return (grab("WC"), grab("MG"))
    }

    // MARK: Apply a value to the draft

    /// Returns true if the value was understood (including an explicit "not specified").
    @discardableResult
    static func apply(_ field: Field, value raw: String, secondary: String? = nil, to d: inout RecipeImportDraft) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let dash = cleanNumberText(value) == "-"
        func setNum(_ key: RecipePropertyKey, _ kp: WritableKeyPath<RecipeSettings, RecipeField<Double>>) -> Bool {
            if dash { d.found.insert(key); return true }
            guard let v = number(value) else { return false }
            d.settings[keyPath: kp] = .value(v); d.found.insert(key); return true
        }
        func setInt(_ key: RecipePropertyKey, _ kp: WritableKeyPath<RecipeSettings, RecipeField<Int>>) -> Bool {
            if dash { d.found.insert(key); return true }
            guard let v = number(value) else { return false }
            d.settings[keyPath: kp] = .value(Int(v.rounded())); d.found.insert(key); return true
        }
        switch field {
        case .property(.filmSimulation):
            guard let sim = filmSimulation(value) else { return false }
            d.settings.filmSimulation = sim; d.filmSimulationFound = true; d.found.insert(.filmSimulation); return true
        case .property(.whiteBalance):
            guard let (mode, k) = whiteBalance(value) else { return false }
            d.settings.whiteBalance = .value(mode)
            if let k { d.settings.kelvin = .value(k); d.found.insert(.kelvin) }
            d.found.insert(.whiteBalance)
            // Shift may be written on the same line: "5200K, +1 Red & -2 Blue"
            let (r, b) = wbShift(value)
            if let r { d.settings.wbShiftRed = .value(r); d.found.insert(.wbShiftRed) }
            if let b { d.settings.wbShiftBlue = .value(b); d.found.insert(.wbShiftBlue) }
            return true
        case .wbShift:
            let (r, b) = wbShift(value)
            if let r { d.settings.wbShiftRed = .value(r); d.found.insert(.wbShiftRed) }
            if let b { d.settings.wbShiftBlue = .value(b); d.found.insert(.wbShiftBlue) }
            return r != nil || b != nil
        case .grain:
            let (rough, size) = grain(value)
            guard let rough else { return dash }
            d.settings.grainRoughness = .value(rough); d.found.insert(.grainRoughness)
            if let size { d.settings.grainSize = .value(size); d.found.insert(.grainSize) }
            if let secondary {
                let (_, s2) = grain(secondary)
                if let s2 { d.settings.grainSize = .value(s2); d.found.insert(.grainSize) }
            }
            return true
        case .property(.grainSize):
            let (_, size) = grain(value)
            if let size { d.settings.grainSize = .value(size); d.found.insert(.grainSize); return true }
            return dash
        case .property(.colorChrome):
            if dash { return true }
            guard let e = effect(value) else { return false }
            d.settings.colorChrome = .value(e); d.found.insert(.colorChrome); return true
        case .property(.colorChromeFXBlue):
            if dash { return true }
            guard let e = effect(value) else { return false }
            d.settings.colorChromeFXBlue = .value(e); d.found.insert(.colorChromeFXBlue); return true
        case .property(.dynamicRange):
            guard let dr = dynamicRange(value) else { return dash }
            d.settings.dynamicRange = .value(dr); d.found.insert(.dynamicRange); return true
        case .property(.dRangePriority):
            guard let p = drPriority(value) else { return dash }
            d.settings.dRangePriority = .value(p); d.found.insert(.dRangePriority); return true
        case .property(.highlight): return setNum(.highlight, \.highlight)
        case .property(.shadow): return setNum(.shadow, \.shadow)
        case .property(.color): return setInt(.color, \.color)
        case .property(.sharpness): return setInt(.sharpness, \.sharpness)
        case .property(.highISONR): return setInt(.highISONR, \.highISONR)
        case .property(.clarity): return setInt(.clarity, \.clarity)
        case .monochromatic:
            let (wc, mg) = monochromatic(value)
            if let wc { d.settings.monochromaticWarmCool = .value(wc); d.found.insert(.monochromaticWarmCool) }
            if let mg { d.settings.monochromaticMagentaGreen = .value(mg); d.found.insert(.monochromaticMagentaGreen) }
            return wc != nil || mg != nil
        case .exposure:
            if dash { return true }
            guard let ev = number(value) else { return false }
            d.settings.suggestedExposureCompensation = .value((ev * 3).rounded() / 3)
            return true
        case .iso:
            if !dash, !value.isEmpty { d.notes.append("ISO: \(value)") }
            return true
        case .property:
            return false
        }
    }

    static func cameraModel(in s: String) -> String? {
        let t = s.uppercased()
        let patterns = [#"X100[A-Z]*"#, #"X-[A-Z]{1,3}\d{1,3}[A-Z]?( (III|II|IV|V))?\b"#, #"GFX ?\d{2,3}[A-Z ]*(II)?"#]
        for p in patterns {
            if let r = t.range(of: p, options: .regularExpression) { return String(t[r]).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    /// Looks up a label, also trying text outside/inside parentheses: "Màu sắc (Color)".
    static func labelField(_ raw: String) -> Field? {
        if let f = labels[normalize(raw)] { return f }
        guard let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close else { return nil }
        let outside = String(raw[..<open]) + String(raw[raw.index(after: close)...])
        let inside = String(raw[raw.index(after: open)..<close])
        return labels[normalize(outside)] ?? labels[normalize(inside)]
    }

    // MARK: Plain text ("Key: Value" lines)

    static func parse(text: String) -> RecipeImportDraft {
        var d = RecipeImportDraft()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let field = labelField(parts[0]) {
                if !apply(field, value: parts[1], to: &d) { d.unrecognized.append(line) }
                continue
            }
            if parts.count == 2, !parts[1].isEmpty, parts[0].count <= 40, i > 0 {
                d.otherSettings.append((parts[0], parts[1]))
                continue
            }
            if i == 0, d.name.isEmpty, !line.contains(":") { d.name = line; continue }
            if d.cameraModel == nil, let cam = cameraModel(in: line) { d.cameraModel = cam; continue }
            d.unrecognized.append(line)
        }
        return d
    }

    // MARK: Card layout (OCR blocks)

    /// Recipe cards print each value directly ABOVE its label. For every label we pick the
    /// nearest unclaimed block above it whose horizontal centre falls within the label's column.
    static func parse(blocks raw: [OCRTextBlock]) -> RecipeImportDraft {
        var d = RecipeImportDraft()
        let blocks = raw.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        var claimed = Set<Int>()

        // Labels (exact label text after normalization). A "Red: x Blue: y" line is the WB label.
        var labelIdx: [(Int, Field)] = []
        for (i, b) in blocks.enumerated() {
            if let f = labels[normalize(b.text)] { labelIdx.append((i, f)); claimed.insert(i) }
            else if wbShift(b.text).red != nil || wbShift(b.text).blue != nil, normalize(b.text).contains("red") {
                labelIdx.append((i, .wbShift)); claimed.insert(i)
            }
        }
        for (i, b) in blocks.enumerated() where isBoilerplate(b.text) {
            claimed.insert(i)
            if normalize(b.text).hasPrefix("madewith") { d.sourceNote = b.text.trimmingCharacters(in: .whitespaces) }
            if normalize(b.text).hasPrefix("filmrecipe") { d.cameraModel = cameraModel(in: b.text) }
        }

        func valuesAbove(_ label: OCRTextBlock, limit: Int) -> [Int] {
            let column = max(label.box.width, 0.06) * 0.75
            return blocks.indices
                .filter { !claimed.contains($0) }
                .filter { blocks[$0].box.maxY <= label.box.minY + 0.006 && label.box.minY - blocks[$0].box.maxY < 0.07 }
                .filter { abs(blocks[$0].midX - label.midX) < column }
                .sorted { (label.box.minY - blocks[$0].box.maxY) < (label.box.minY - blocks[$1].box.maxY) }
                .prefix(limit).map { $0 }
        }

        // Process the labels top-to-bottom so each value is claimed by the label just below it.
        for (li, field) in labelIdx.sorted(by: { blocks[$0.0].box.minY < blocks[$1.0].box.minY }) {
            let label = blocks[li]
            switch field {
            case .wbShift where labels[normalize(label.text)] == .wbShift:
                // An explicit "WB Shift" label: the shift values are in the tile above it.
                if let v = valuesAbove(label, limit: 1).first {
                    claimed.insert(v)
                    if !apply(.wbShift, value: blocks[v].text, to: &d) { d.unrecognized.append(blocks[v].text) }
                } else {
                    d.missing[.wbShiftRed] = region(above: label)
                }
            case .wbShift:
                // A "Red: x Blue: y" line acting as the label under the white balance value.
                apply(.wbShift, value: label.text, to: &d)
                if let v = valuesAbove(label, limit: 1).first {
                    claimed.insert(v)
                    if !apply(.property(.whiteBalance), value: blocks[v].text, to: &d) { d.unrecognized.append(blocks[v].text) }
                } else {
                    d.missing[.whiteBalance] = region(above: label)
                }
            case .grain:
                // Card shows roughness above size ("Off" over "-").
                let above = valuesAbove(label, limit: 2)
                above.forEach { claimed.insert($0) }
                if above.isEmpty { d.missing[.grainRoughness] = region(above: label); continue }
                let near = blocks[above[0]].text
                let far = above.count > 1 ? blocks[above[1]].text : nil
                if let far { apply(.grain, value: far, secondary: near, to: &d) }
                else if !apply(.grain, value: near, to: &d) { d.unrecognized.append(near) }
            default:
                if let v = valuesAbove(label, limit: 1).first {
                    claimed.insert(v)
                    if !apply(field, value: blocks[v].text, to: &d) {
                        d.unrecognized.append("\(label.text): \(blocks[v].text)")
                        if case .property(let k) = field { d.missing[k] = region(above: label) }
                    }
                } else if case .property(let k) = field {
                    d.missing[k] = region(above: label)
                }
            }
        }

        // Title: the tallest unclaimed block in the top 15% of the card.
        let top = blocks.indices.filter { !claimed.contains($0) && blocks[$0].box.minY < 0.15 }
        if let t = top.max(by: { blocks[$0].box.height < blocks[$1].box.height }) {
            d.name = blocks[t].text.trimmingCharacters(in: .whitespaces); claimed.insert(t)
        }
        // Credit: an unclaimed short line between the header and the settings grid (usually a
        // watermark on the sample photo), e.g. "@handle".
        let firstValueY = labelIdx.map { blocks[$0.0].box.minY }.min() ?? 1
        if let c = blocks.indices.first(where: { !claimed.contains($0) && blocks[$0].box.minY > 0.15 && blocks[$0].box.minY < firstValueY - 0.05
            && blocks[$0].text.count <= 32 }) {
            d.credit = blocks[c].text.trimmingCharacters(in: .whitespaces); claimed.insert(c)
        }
        for i in blocks.indices where !claimed.contains(i) { d.unrecognized.append(blocks[i].text) }
        return d
    }

    /// Where a missing value should be (directly above its label), for a cropped OCR retry.
    static func region(above label: OCRTextBlock) -> CGRect {
        let w = max(label.box.width * 1.8, 0.16)
        let h: CGFloat = 0.075
        return CGRect(x: label.midX - w / 2, y: max(0, label.box.minY - h), width: w, height: h)
    }

    /// Merges an OCR retry result for one property into the draft.
    static func fill(_ key: RecipePropertyKey, from text: String, into d: inout RecipeImportDraft) {
        let field: Field = key == .grainRoughness ? .grain : .property(key)
        if apply(field, value: text, to: &d) { d.missing.removeValue(forKey: key) }
    }
}
