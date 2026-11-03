import SwiftUI
import CoreGraphics

// FilmLab design system components. Chrome is native SwiftUI, so on iOS 26+ buttons, chips
// and photo pills render as Liquid Glass; iOS 17–25 falls back to bordered system styles.

/// Circular icon button: glass on iOS 26+, bordered before. `isOn` makes it prominent.
struct CircleIconButton: View {
    var systemName: String
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 44
    var isOn = false
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .medium))
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .tint(isOn ? Theme.accent : nil)
        .foregroundStyle(isOn ? Theme.onAccent : tint)
        .modifier(GlassButtonShape(prominent: isOn, shape: .circle))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Section title with an optional "See All" link, in the style of the system's grouped lists.
struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) { ArrowLink(title: actionTitle) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// "See All ›" link.
struct ArrowLink: View {
    var title: String
    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
        }
        .font(.body)
        .foregroundStyle(.tint)
        .padding(.vertical, 6)
    }
}

/// Selectable chip: glass (prominent when selected) on iOS 26+, bordered before.
struct PillChip: View {
    var emoji: String? = nil
    var systemImage: String? = nil
    var title: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji { Text(emoji) }
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .fixedSize()
            .padding(.vertical, 2)
        }
        .tint(selected ? Theme.accent : nil)
        .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
        .chipStyle(selected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Label pill laid over a photo: clear glass (or a dark tinted glass tag) on iOS 26+.
struct PhotoPill: View {
    var title: String
    var systemImage: String? = nil
    var dark = false
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(dark ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .floatingCapsule(tint: dark ? .black.opacity(0.45) : nil)
        .fixedSize()
    }
}

/// Project-style card: big rounded 4:3 photo with pills, light title and simulation underneath.
struct PhotoRecipeCard: View {
    var recipe: FilmRecipe
    var thumbnail: CGImage?
    var width: CGFloat? = 260
    var saved = false
    /// Cover photo published on the website; replaces the rendered thumbnail when present.
    var coverURL: URL? = nil
    var coverLabel = "Approximate"

    @ViewBuilder private var fallback: some View {
        if let thumbnail { CGImageView(image: thumbnail, contentMode: .fill) } else { Theme.swatch(for: recipe.filmSimulation) }
    }

    /// Grid cells (no fixed width) and narrow cards: one pill and a smaller title.
    private var compact: Bool { (width ?? 0) < 220 }
    private var radius: CGFloat { compact ? 20 : Theme.corner }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay {
                    if let coverURL {
                        AsyncImage(url: coverURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                            if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { fallback }
                        }
                    } else {
                        fallback
                    }
                }
                .clipped()
                .background(Theme.surface)
                .overlay(alignment: .topLeading) {
                    // Rendered thumbnails are FilmLab's approximation; web covers keep the site's label.
                    if !compact { PhotoPill(title: coverURL == nil ? "Approximate" : coverLabel).padding(10) }
                }
                .overlay(alignment: .topTrailing) {
                    if let g = recipe.inferredGeneration { PhotoPill(title: g.displayName, dark: true).padding(10) }
                }
                .overlay(alignment: .bottomLeading) {
                    // Status only (not a button): shows real library state, never invented counts.
                    if saved || recipe.isFavorite {
                        PhotoPill(title: recipe.isFavorite ? "Favorite" : "In Library",
                                  systemImage: recipe.isFavorite ? "heart.fill" : "checkmark").padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                    Text(recipe.name)
                        .font(compact ? .headline : .title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(recipe.filmSimulation.displayName)
                        .font(compact ? .footnote : .subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.name), \(recipe.filmSimulation.displayName)\(recipe.inferredGeneration.map { ", \($0.displayName)" } ?? "")\(saved ? ", in library" : "")")
    }
}

/// Small "X-Trans V" tag for lists and detail.
struct GenerationBadge: View {
    var generation: XTransGeneration
    var body: some View {
        Text(generation.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.background, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.chipStroke, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(generation.displayName)
    }
}

/// "DESTINATION" card used to choose a camera slot and run the primary camera action.
struct DestinationCard<Picker: View>: View {
    var eyebrow = "DESTINATION"
    var slot: CameraSlot
    var title: String
    var subtitle: String
    var ctaTitle: String
    var ctaIcon = "square.and.arrow.down"
    var ctaEnabled = true
    var ctaRole: ButtonRole? = nil
    var ctaIdentifier = "destinationCTA"
    @ViewBuilder var picker: () -> Picker
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(eyebrow, systemImage: "camera.aperture").eyebrowStyle()
            Menu {
                picker()
            } label: {
                HStack(spacing: 16) {
                    Text(slot.label)
                        .font(.system(size: 30, weight: .regular).monospacedDigit()).tracking(-1)
                        .foregroundStyle(Theme.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            }
            .accessibilityIdentifier("slotPicker")
            Button(role: ctaRole, action: action) {
                Label(ctaTitle, systemImage: ctaIcon)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(ctaRole == .destructive ? Theme.danger : Theme.accent)
            .foregroundStyle(Theme.onAccent)
            .primaryActionStyle()
            .disabled(!ctaEnabled)
            .accessibilityIdentifier(ctaIdentifier)
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Full-width primary action (glass-prominent capsule on iOS 26+).
struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            PrimaryButtonLabel(title: title, systemImage: systemImage)
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.onAccent)
        .primaryActionStyle()
        .disabled(!enabled)
    }
}

/// Content of a full-width action. Style the enclosing control with `primaryActionStyle()` or
/// `secondaryActionStyle()` (works for `Button`, `PhotosPicker` and `ShareLink`).
struct PrimaryButtonLabel: View {
    var title: String
    var systemImage: String? = nil
    var enabled = true
    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }
}

typealias SecondaryButtonLabel = PrimaryButtonLabel
