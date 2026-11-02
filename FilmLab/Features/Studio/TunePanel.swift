import SwiftUI

/// One tunable recipe property: how to display it, step it with −/+, and when it applies.
/// Ranges come from the camera profile; inapplicable properties stay visible with a reason.
struct TuneParameter: Identifiable {
    let id: String
    let label: String          // short uppercase card label
    let name: String           // full accessible name
    let palette: [Color]
    let display: (RecipeSettings) -> String
    let isSet: (RecipeSettings) -> Bool
    let isApplicable: (RecipeSettings) -> Bool
    let naReason: (RecipeSettings) -> String
    let step: (RecipeSettings, Int) -> RecipeSettings
    let clear: (RecipeSettings) -> RecipeSettings
    let canStep: (RecipeSettings, Int) -> Bool
}

extension TuneParameter {
    static func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + RecipeValidator.format(v) }

    static func numeric(_ id: String, _ label: String, _ name: String, _ kp: WritableKeyPath<RecipeSettings, RecipeField<Double>>,
                        range: NumericRange, palette: [Color], na: String = "") -> TuneParameter {
        let origin = range.clamp(0)
        return TuneParameter(
            id: id, label: label, name: name, palette: palette,
            display: { s in
                switch s[keyPath: kp] { case .unset: "—"; case .notApplicable: "n/a"; case .value(let v): signed(v) }
            },
            isSet: { $0[keyPath: kp].isSet },
            isApplicable: { $0[keyPath: kp] != .notApplicable },
            naReason: { _ in na },
            step: { s, dir in
                var c = s
                let current = c[keyPath: kp].concreteValue
                c[keyPath: kp] = .value(current == nil ? origin : range.clamp(current! + Double(dir) * range.step))
                return c.normalized()
            },
            clear: { s in var c = s; c[keyPath: kp] = .unset; return c.normalized() },
            canStep: { s, dir in
                guard s[keyPath: kp] != .notApplicable else { return false }
                guard let v = s[keyPath: kp].concreteValue else { return true }
                return dir > 0 ? v < range.max - 1e-9 : v > range.min + 1e-9
            })
    }

    static func integer(_ id: String, _ label: String, _ name: String, _ kp: WritableKeyPath<RecipeSettings, RecipeField<Int>>,
                        range: NumericRange, stepSize: Int? = nil, signed isSigned: Bool = true, suffix: String = "",
                        palette: [Color], na: String = "") -> TuneParameter {
        let stepBy = stepSize ?? Int(range.step)
        let origin = Int(range.clamp(range.min <= 0 && range.max >= 0 ? 0 : (range.min + range.max) / 2))
        return TuneParameter(
            id: id, label: label, name: name, palette: palette,
            display: { s in
                switch s[keyPath: kp] {
                case .unset: "—"
                case .notApplicable: "n/a"
                case .value(let v): (isSigned && v > 0 ? "+" : "") + "\(v)" + suffix
                }
            },
            isSet: { $0[keyPath: kp].isSet },
            isApplicable: { $0[keyPath: kp] != .notApplicable },
            naReason: { _ in na },
            step: { s, dir in
                var c = s
                let current = c[keyPath: kp].concreteValue
                let next = current == nil ? origin : current! + dir * stepBy
                c[keyPath: kp] = .value(Int(range.clamp(Double(next))))
                return c.normalized()
            },
            clear: { s in var c = s; c[keyPath: kp] = .unset; return c.normalized() },
            canStep: { s, dir in
                guard s[keyPath: kp] != .notApplicable else { return false }
                guard let v = s[keyPath: kp].concreteValue else { return true }
                return dir > 0 ? Double(v) < range.max : Double(v) > range.min
            })
    }

    static func choice<T: Equatable & Hashable & Codable & Sendable>(
        _ id: String, _ label: String, _ name: String, _ kp: WritableKeyPath<RecipeSettings, RecipeField<T>>,
        options: [T], title: @escaping (T) -> String, palette: [Color], na: String = "") -> TuneParameter {
        TuneParameter(
            id: id, label: label, name: name, palette: palette,
            display: { s in
                switch s[keyPath: kp] { case .unset: "—"; case .notApplicable: "n/a"; case .value(let v): title(v) }
            },
            isSet: { $0[keyPath: kp].isSet },
            isApplicable: { $0[keyPath: kp] != .notApplicable },
            naReason: { _ in na },
            step: { s, dir in
                var c = s
                if let v = c[keyPath: kp].concreteValue, let i = options.firstIndex(of: v) {
                    c[keyPath: kp] = .value(options[min(max(i + dir, 0), options.count - 1)])
                } else {
                    c[keyPath: kp] = .value(dir > 0 ? options[0] : options[options.count - 1])
                }
                return c.normalized()
            },
            clear: { s in var c = s; c[keyPath: kp] = .unset; return c.normalized() },
            canStep: { s, dir in
                guard s[keyPath: kp] != .notApplicable else { return false }
                guard let v = s[keyPath: kp].concreteValue, let i = options.firstIndex(of: v) else { return true }
                return dir > 0 ? i < options.count - 1 : i > 0
            })
    }

    /// All parameters in display order, using the profile's capability ranges.
    static func all(profile: CameraProfile = .xt30III) -> [TuneParameter] {
        func r(_ k: RecipePropertyKey) -> NumericRange { profile.capability(k)?.range ?? NumericRange(min: -4, max: 4, step: 1) }
        let drpNA = "D RANGE PRIORITY is on: the camera sets this automatically. Set D RANGE PRIORITY to OFF to adjust."
        let rainbow: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
        let teal: [Color] = [Theme.accent, Color(red: 0.1, green: 0.35, blue: 0.4)]
        let effect = EffectLevel.allCases
        return [
            .numeric("highlight", "HIGHLIGHT", "Highlight", \.highlight, range: r(.highlight),
                     palette: [Color(white: 0.95), Color(white: 0.55)], na: drpNA),
            .numeric("shadow", "SHADOW", "Shadow", \.shadow, range: r(.shadow),
                     palette: [Color(white: 0.45), Color(white: 0.08)], na: drpNA),
            .integer("color", "COLOR", "Color", \.color, range: r(.color), palette: rainbow,
                     na: "COLOR doesn't apply to black-and-white simulations."),
            .choice("cc", "CHROME", "Color Chrome Effect", \.colorChrome, options: effect, title: { $0.displayName.capitalized },
                    palette: [Color(red: 0.75, green: 0.2, blue: 0.2), Color(red: 0.35, green: 0.1, blue: 0.15)]),
            .choice("ccb", "CCE BLUE", "Color Chrome FX Blue", \.colorChromeFXBlue, options: effect, title: { $0.displayName.capitalized },
                    palette: [Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.05, green: 0.12, blue: 0.35)]),
            .choice("grain", "GRAIN", "Grain Effect", \.grainRoughness, options: GrainRoughness.allCases, title: { $0.displayName.capitalized },
                    palette: [Color(white: 0.6), Color(white: 0.25)]),
            .choice("grainSize", "GRAIN SIZE", "Grain Size", \.grainSize, options: GrainSize.allCases, title: { $0.displayName.capitalized },
                    palette: [Color(white: 0.5), Color(white: 0.2)], na: "Grain size applies only when Grain Effect is on."),
            .choice("wb", "WHITE BAL.", "White Balance", \.whiteBalance, options: WhiteBalanceMode.allCases, title: { $0.displayName.capitalized },
                    palette: [Color(red: 0.98, green: 0.7, blue: 0.35), Color(red: 0.35, green: 0.55, blue: 0.95)]),
            .integer("kelvin", "KELVIN", "Color Temperature", \.kelvin, range: r(.kelvin), stepSize: 100, signed: false, suffix: "K",
                     palette: [Color(red: 1, green: 0.6, blue: 0.25), Color(red: 0.45, green: 0.65, blue: 1)],
                     na: "Set White Balance to Color Temperature to choose a Kelvin value."),
            .integer("wbr", "WB RED", "White balance shift red", \.wbShiftRed, range: r(.wbShiftRed),
                     palette: [Color(red: 0.9, green: 0.25, blue: 0.25), Color(red: 0.2, green: 0.6, blue: 0.6)]),
            .integer("wbb", "WB BLUE", "White balance shift blue", \.wbShiftBlue, range: r(.wbShiftBlue),
                     palette: [Color(red: 0.25, green: 0.4, blue: 0.95), Color(red: 0.85, green: 0.75, blue: 0.2)]),
            .choice("dr", "DYN. RANGE", "Dynamic Range", \.dynamicRange, options: DynamicRangeSetting.allCases, title: { $0.displayName },
                    palette: [Color(white: 0.85), Color(white: 0.2)], na: drpNA),
            .choice("drp", "DR PRIORITY", "D Range Priority", \.dRangePriority, options: DRangePriority.allCases, title: { $0.displayName.capitalized },
                    palette: [Color(white: 0.75), Color(red: 0.2, green: 0.25, blue: 0.3)]),
            .integer("sharp", "SHARPNESS", "Sharpness", \.sharpness, range: r(.sharpness), palette: teal),
            .integer("nr", "NOISE RED.", "High ISO noise reduction", \.highISONR, range: r(.highISONR), palette: teal),
            .integer("clarity", "CLARITY", "Clarity", \.clarity, range: r(.clarity), palette: teal),
            .integer("wc", "MONO WC", "Monochromatic warm–cool", \.monochromaticWarmCool, range: r(.monochromaticWarmCool),
                     palette: [Color(red: 0.95, green: 0.65, blue: 0.35), Color(red: 0.4, green: 0.6, blue: 0.95)],
                     na: "Monochromatic color applies only to ACROS and MONOCHROME."),
            .integer("mg", "MONO MG", "Monochromatic magenta–green", \.monochromaticMagentaGreen, range: r(.monochromaticMagentaGreen),
                     palette: [Color(red: 0.85, green: 0.35, blue: 0.75), Color(red: 0.35, green: 0.8, blue: 0.45)],
                     na: "Monochromatic color applies only to ACROS and MONOCHROME."),
            .numeric("ev", "EXPOSURE", "Suggested exposure compensation (preview only)", \.suggestedExposureCompensation,
                     range: NumericRange(min: -3, max: 3, step: 1.0 / 3.0), palette: [Color(white: 0.9), Color(white: 0.3)]),
        ]
    }
}

/// Horizontal parameter cards + large −/+ stepper.
struct TunePanel: View {
    @Binding var settings: RecipeSettings
    var hapticsEnabled = true
    @State private var selectedID = "highlight"
    private let parameters = TuneParameter.all()

    private var selected: TuneParameter { parameters.first { $0.id == selectedID } ?? parameters[0] }

    var body: some View {
        VStack(spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(parameters) { p in
                            ParameterCard(parameter: p, settings: settings, selected: p.id == selectedID)
                                .id(p.id)
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.3)) { selectedID = p.id; proxy.scrollTo(p.id, anchor: .center) }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("param-\(p.id)")
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 4)
                }
            }
            stepper
            footnote
        }
        .sensoryFeedback(.selection, trigger: hapticsEnabled ? selected.display(settings) : "")
    }

    private var stepper: some View {
        let p = selected
        let applicable = p.isApplicable(settings)
        return HStack(spacing: 44) {
            CircleIconButton(systemName: "minus", tint: Theme.accent, size: 56, accessibilityLabel: "Decrease \(p.name)") {
                settings = p.step(settings, -1)
            }
            .disabled(!p.canStep(settings, -1))
            .opacity(p.canStep(settings, -1) ? 1 : 0.4)
            Text(p.display(settings))
                .font(.system(size: 34, weight: .bold).monospacedDigit())
                .foregroundStyle(applicable ? Theme.textPrimary : Theme.textTertiary)
                .frame(minWidth: 110)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy, value: p.display(settings))
            CircleIconButton(systemName: "plus", tint: Theme.textSecondary, size: 56, accessibilityLabel: "Increase \(p.name)") {
                settings = p.step(settings, 1)
            }
            .disabled(!p.canStep(settings, 1))
            .opacity(p.canStep(settings, 1) ? 1 : 0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.name)
        .accessibilityValue(applicable ? (p.isSet(settings) ? p.display(settings) : "Not set") : "Not applicable")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: settings = p.step(settings, 1)
            case .decrement: settings = p.step(settings, -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("tuneStepper")
    }

    @ViewBuilder private var footnote: some View {
        let p = selected
        if !p.isApplicable(settings) {
            Text(p.naReason(settings)).font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.gutter)
        } else if p.isSet(settings) {
            Button("Clear — camera keeps its own value") { settings = p.clear(settings) }
                .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
        } else {
            Text("Not set — writing this recipe leaves the camera's value as-is.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        if p.id == "ev" {
            Text("A recipe note, not a camera slot setting. Applied to the approximate preview.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }
}

struct ParameterCard: View {
    var parameter: TuneParameter
    var settings: RecipeSettings
    var selected: Bool

    var body: some View {
        let applicable = parameter.isApplicable(settings)
        let shape = RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
        VStack(spacing: 6) {
            Text(parameter.label)
                .font(.caption.weight(.semibold)).tracking(1.2)
                .foregroundStyle(selected ? .white.opacity(0.92) : Theme.textSecondary)
            Text(parameter.display(settings))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(selected ? .white : (applicable ? Theme.textPrimary.opacity(0.8) : Theme.textTertiary))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .shadow(color: selected ? .black.opacity(0.35) : .clear, radius: 3)
        .frame(width: 124, height: 78)
        .background {
            ZStack {
                Theme.surface
                LinearGradient(colors: parameter.palette, startPoint: .leading, endPoint: .trailing)
                    .opacity(selected ? 0.95 : 0.14)
            }
            .clipShape(shape)
        }
        .overlay(shape.stroke(selected ? Color.white.opacity(0.75) : Theme.hairline, lineWidth: selected ? 2 : 1))
        .shadow(color: selected ? parameter.palette.first!.opacity(0.45) : .clear, radius: 12)
        .opacity(applicable ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parameter.name)
        .accessibilityValue(applicable ? parameter.display(settings) : "Not applicable")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
