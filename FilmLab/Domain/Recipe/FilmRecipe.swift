import Foundation

/// Where a recipe came from. Shown in the UI so attribution and licensing are never lost.
struct RecipeProvenance: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Written by the FilmLab project and shipped with the app.
        case filmLabOriginal
        /// Created on this device by the user.
        case userCreated
        /// Duplicated from another recipe (see `derivedFrom`).
        case duplicated
        /// Imported from a FilmLab JSON file.
        case imported
        /// Read from a camera C slot.
        case cameraSlot
    }

    var kind: Kind
    var author: String?
    var sourceURL: URL?
    var license: String?
    var derivedFrom: UUID?
    var note: String?

    static let userCreated = RecipeProvenance(kind: .userCreated)
}

/// Descriptive tags used by Explore filters. Values are FilmLab's own subjective labels.
enum RecipeMood: String, Codable, CaseIterable, Sendable, Hashable {
    case warm, cool, neutral, highContrast, lowContrast, muted, vivid, vintage, cinematic, blackAndWhite
    var displayName: String {
        switch self {
        case .warm: "Warm"
        case .cool: "Cool"
        case .neutral: "Neutral"
        case .highContrast: "High contrast"
        case .lowContrast: "Low contrast"
        case .muted: "Muted"
        case .vivid: "Vivid"
        case .vintage: "Vintage"
        case .cinematic: "Cinematic"
        case .blackAndWhite: "B&W"
        }
    }
}

struct FilmRecipe: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var settings: RecipeSettings
    var tags: [String]
    var moods: [RecipeMood]
    var isFavorite: Bool
    /// Camera model identifiers this recipe was authored/validated for, e.g. "X-T30 III".
    var compatibleCameras: [String]
    /// Recipe family the recipe was written for ("IV" / "V"); nil = unknown. Optional in JSON
    /// (older files and apps omit it). Use `inferredGeneration` for display and filtering.
    var xTransGeneration: XTransGeneration?
    var provenance: RecipeProvenance
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        settings: RecipeSettings,
        tags: [String] = [],
        moods: [RecipeMood] = [],
        isFavorite: Bool = false,
        compatibleCameras: [String] = [CameraProfile.xt30III.modelName],
        xTransGeneration: XTransGeneration? = nil,
        provenance: RecipeProvenance = .userCreated,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.settings = settings.normalized()
        self.tags = tags
        self.moods = moods
        self.isFavorite = isFavorite
        self.compatibleCameras = compatibleCameras
        self.xTransGeneration = xTransGeneration
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var filmSimulation: FilmSimulation { settings.filmSimulation }

    /// Creates an editable copy with fresh identity and provenance pointing back here.
    func duplicated(named newName: String? = nil, now: Date = Date()) -> FilmRecipe {
        FilmRecipe(
            name: newName ?? "\(name) Copy",
            summary: summary,
            settings: settings,
            tags: tags,
            moods: moods,
            isFavorite: false,
            compatibleCameras: compatibleCameras,
            xTransGeneration: xTransGeneration,
            provenance: RecipeProvenance(
                kind: .duplicated,
                author: provenance.author,
                sourceURL: provenance.sourceURL,
                license: provenance.license,
                derivedFrom: id,
                note: "Duplicated from “\(name)”"
            ),
            createdAt: now,
            updatedAt: now
        )
    }
}

/// A named arrangement of up to seven recipes for C1–C7. Recipes are referenced by ID so
/// edits to a recipe flow into the Set; a missing recipe shows as an empty slot.
struct RecipeSet: Codable, Identifiable, Equatable, Hashable, Sendable {
    static let slotCount = 7

    var id: UUID
    var name: String
    var notes: String
    /// Always exactly 7 entries; index 0 = C1.
    var slots: [UUID?]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, notes: String = "", slots: [UUID?] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.notes = notes
        self.slots = Self.padded(slots)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func padded(_ slots: [UUID?]) -> [UUID?] {
        let trimmed = Array(slots.prefix(slotCount))
        return trimmed + Array(repeating: nil, count: slotCount - trimmed.count)
    }

    mutating func assign(_ recipeID: UUID?, to slot: CameraSlot) {
        slots[slot.index] = recipeID
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var copy = slots
        let moving = source.sorted().map { copy[$0] }
        for i in source.sorted(by: >) { copy.remove(at: i) }
        let insertAt = destination - source.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: min(max(insertAt, 0), copy.count))
        slots = Self.padded(copy)
    }

    var filledCount: Int { slots.compactMap { $0 }.count }
}
