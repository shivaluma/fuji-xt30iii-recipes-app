import Foundation

/// A single recipe property with explicit "no value" semantics.
///
/// - `unset`: the recipe author did not specify it (camera keeps whatever it has / default).
/// - `notApplicable`: the value cannot apply given other settings (e.g. COLOR on ACROS,
///   Kelvin when white balance isn't COLOR TEMPERATURE, highlight while D RANGE PRIORITY is on).
/// - `value`: a concrete value — note `0` / `.off` are concrete values, distinct from `unset`.
///
/// JSON encoding is an explicit tagged object so schema readers never confuse 0 with unset:
/// `{"state":"value","value":0}`, `{"state":"unset"}`, `{"state":"notApplicable"}`.
enum RecipeField<Value: Codable & Equatable & Hashable & Sendable>: Codable, Equatable, Hashable, Sendable {
    case unset
    case notApplicable
    case value(Value)

    var concreteValue: Value? {
        if case .value(let v) = self { return v }
        return nil
    }

    var isSet: Bool { concreteValue != nil }

    func value(or fallback: Value) -> Value { concreteValue ?? fallback }

    private enum CodingKeys: String, CodingKey { case state, value }
    private enum State: String, Codable { case unset, notApplicable, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(State.self, forKey: .state) {
        case .unset: self = .unset
        case .notApplicable: self = .notApplicable
        case .value: self = .value(try c.decode(Value.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unset: try c.encode(State.unset, forKey: .state)
        case .notApplicable: try c.encode(State.notApplicable, forKey: .state)
        case .value(let v):
            try c.encode(State.value, forKey: .state)
            try c.encode(v, forKey: .value)
        }
    }
}

extension RecipeField: CustomStringConvertible {
    var description: String {
        switch self {
        case .unset: "—"
        case .notApplicable: "n/a"
        case .value(let v): "\(v)"
        }
    }
}
