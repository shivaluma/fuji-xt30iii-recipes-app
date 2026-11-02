import Foundation

/// One row of the before/after diff shown before any camera write.
struct SettingDiffRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case unchanged
        case changed
        /// The recipe doesn't specify this; the camera keeps its current value.
        case keepsCameraValue
        /// Not applicable with the new settings (e.g. COLOR on ACROS).
        case notApplicable
    }

    var key: RecipePropertyKey
    var before: String
    var after: String
    var kind: Kind
    var id: RecipePropertyKey { key }
}

enum SlotDiff {
    static func display(_ key: RecipePropertyKey, _ s: RecipeSettings?) -> String {
        guard let s else { return "—" }
        func num(_ f: RecipeField<Double>) -> String {
            switch f {
            case .unset: return "—"
            case .notApplicable: return "n/a"
            case .value(let v): return (v > 0 ? "+" : "") + RecipeValidator.format(v)
            }
        }
        func int(_ f: RecipeField<Int>, signed: Bool = true) -> String {
            switch f {
            case .unset: return "—"
            case .notApplicable: return "n/a"
            case .value(let v): return signed && v > 0 ? "+\(v)" : "\(v)"
            }
        }
        func en<T>(_ f: RecipeField<T>, _ name: (T) -> String) -> String {
            switch f {
            case .unset: return "—"
            case .notApplicable: return "n/a"
            case .value(let v): return name(v)
            }
        }
        switch key {
        case .filmSimulation: return s.filmSimulation.displayName
        case .grainRoughness: return en(s.grainRoughness) { $0.displayName }
        case .grainSize: return en(s.grainSize) { $0.displayName }
        case .colorChrome: return en(s.colorChrome) { $0.displayName }
        case .colorChromeFXBlue: return en(s.colorChromeFXBlue) { $0.displayName }
        case .whiteBalance: return en(s.whiteBalance) { $0.displayName }
        case .kelvin: return en(s.kelvin) { "\($0)K" }
        case .wbShiftRed: return int(s.wbShiftRed)
        case .wbShiftBlue: return int(s.wbShiftBlue)
        case .dynamicRange: return en(s.dynamicRange) { $0.displayName }
        case .dRangePriority: return en(s.dRangePriority) { $0.displayName }
        case .highlight: return num(s.highlight)
        case .shadow: return num(s.shadow)
        case .color: return int(s.color)
        case .sharpness: return int(s.sharpness)
        case .highISONR: return int(s.highISONR)
        case .clarity: return int(s.clarity)
        case .monochromaticWarmCool: return int(s.monochromaticWarmCool)
        case .monochromaticMagentaGreen: return int(s.monochromaticMagentaGreen)
        }
    }

    /// Diff between what the slot holds now and what writing `new` would produce.
    static func rows(before: RecipeSettings?, new rawNew: RecipeSettings) -> [SettingDiffRow] {
        let new = rawNew.normalized()
        return RecipePropertyKey.allCases.map { key in
            let b = display(key, before)
            let a = display(key, new)
            let kind: SettingDiffRow.Kind
            if a == "n/a" { kind = .notApplicable }
            else if a == "—" { kind = .keepsCameraValue }
            else if a == b { kind = .unchanged }
            else { kind = .changed }
            return SettingDiffRow(key: key, before: b, after: kind == .keepsCameraValue ? b : a, kind: kind)
        }
    }
}

/// Records slot-backup files on disk (JSON, one per backup). Local only; never uploaded.
struct CameraBackupStore: Sendable {
    let directory: URL

    func save(_ backup: CameraBackup) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: backup.createdAt).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("backup-\(stamp)-\(backup.id.uuidString.prefix(8)).json")
        try LibraryPersistence.encoder().encode(backup).write(to: url, options: [.atomic])
        return url
    }

    func loadAll() -> [CameraBackup] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? LibraryPersistence.decoder().decode(CameraBackup.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fileURL(for backup: CameraBackup) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.lastPathComponent.contains(backup.id.uuidString.prefix(8)) }
    }

    func delete(_ backup: CameraBackup) {
        if let u = fileURL(for: backup) { try? FileManager.default.removeItem(at: u) }
    }
}
