import SwiftUI
import CoreGraphics

// FilmLab design system components, matching the website: a "©FilmLab" wordmark box, light
// display titles with tight tracking, soft grey circle buttons, ink-black pills for primary
// actions and selection, big rounded 4:3 photo cards with white/black pills, and a floating
// capsule tab bar.

/// Circular icon button on a soft grey panel (the web's `bg-surface` round buttons).
struct CircleIconButton: View {
    var systemName: String
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 44
    /// Filled ink-black when the control is on (e.g. a toggle in the Studio header).
    var isOn = false
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIconLabel(systemName: systemName, tint: tint, size: size, isOn: isOn)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Same look as `CircleIconButton`, for use as a `Menu` label.
struct CircleIconLabel: View {
    var systemName: String
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 44
    var isOn = false
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(isOn ? Theme.onAccent : tint)
            .frame(width: size, height: size)
            .background(isOn ? Theme.accent : Theme.surface, in: Circle())
            .overlay(Circle().stroke(isOn ? Color.clear : Theme.hairline, lineWidth: 1))
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

/// The web nav's grey box with the "©FilmLab" wordmark.
struct Wordmark: View {
    var body: some View {
        Text("©FilmLab")
            .font(Theme.Font.wordmark).tracking(-0.3)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Root-screen header: wordmark box and circular actions on top, a large light title below.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Wordmark()
                Spacer(minLength: 8)
                trailing()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.Font.screenTitle).tracking(Theme.Tracking.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.body).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }
}

/// Section title in the web's uppercase display style, with an optional "See all ↗" link.
struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.Font.sectionTitle).tracking(Theme.Tracking.sectionTitle)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(Theme.Font.sectionSubtitle).foregroundStyle(Theme.textSecondary) }
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

/// Uppercase tracked link with an up-right arrow (the web's "See all ↗").
struct ArrowLink: View {
    var title: String
    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Image(systemName: "arrow.up.right").font(.caption2.weight(.semibold))
        }
        .eyebrowStyle(Theme.textPrimary)
        .padding(.vertical, 6)
    }
}

/// Chip: soft grey with a hairline; ink-black with white text when selected.
struct PillChip: View {
    var emoji: String? = nil
    var systemImage: String? = nil
    var title: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let emoji { Text(emoji).font(.body) }
                if let systemImage { Image(systemName: systemImage).font(.subheadline.weight(.medium)) }
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
            .background(selected ? Theme.accent : Theme.background, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.chipStroke, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// White label pill (or black tag pill) laid over a photo.
struct PhotoPill: View {
    var title: String
    var systemImage: String? = nil
    var dark = false
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(dark ? Color.white : Theme.photoPillText)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(dark ? Theme.photoTag : Theme.photoPill, in: Capsule())
        .fixedSize()
    }
}

/// Project-style card: big rounded 4:3 photo with pills, light title and simulation underneath.
struct PhotoRecipeCard: View {
    var recipe: FilmRecipe
    var thumbnail: CGImage?
    var width: CGFloat? = 260
    var saved = false

    /// Grid cells (no fixed width) and narrow cards: one pill and a smaller title.
    private var compact: Bool { (width ?? 0) < 220 }
    private var radius: CGFloat { compact ? 20 : Theme.corner }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            Color.clear
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay {
                    if let thumbnail { CGImageView(image: thumbnail, contentMode: .fill) } else { Theme.swatch(for: recipe.filmSimulation) }
                }
                .clipped()
                .background(Theme.surface)
                .overlay(alignment: .topLeading) {
                    // Thumbnails are FilmLab's on-device approximation, labelled as on the web.
                    if !compact { PhotoPill(title: "Approximate").padding(10) }
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
                        .font(compact ? .system(size: 17, weight: .regular) : Theme.Font.cardTitle)
                        .tracking(compact ? -0.4 : Theme.Tracking.cardTitle)
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(recipe.filmSimulation.displayName)
                        .font(compact ? .footnote : .subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(Theme.textTertiary)
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

/// Floating capsule tab bar: frosted white, uppercase labels, the selected tab on an ink pill.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    private func item(_ tab: AppTab) -> (String, String) {
        switch tab {
        case .explore: ("Explore", "sparkles")
        case .library: ("Library", "books.vertical")
        case .studio: ("Studio", "camera.filters")
        case .camera: ("Camera", "camera")
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let (title, icon) = item(tab)
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon).font(.system(size: 18, weight: .medium))
                        Text(title).font(.system(size: 10, weight: .medium)).textCase(.uppercase).tracking(0.6)
                    }
                    .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selected { Capsule().fill(Theme.accent) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .background(Theme.background.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
        .padding(.horizontal, 16)
        .animation(.snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
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
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(ctaEnabled ? Theme.onAccent : Theme.textTertiary)
                    .background(ctaEnabled ? Theme.accent : Theme.surfaceRaised, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!ctaEnabled)
            .accessibilityIdentifier(ctaIdentifier)
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Full-width primary action: an ink-black pill (the web's `pillDark`).
struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            PrimaryButtonLabel(title: title, systemImage: systemImage, enabled: enabled)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

/// The primary pill's look, for `PhotosPicker`, `ShareLink` and other non-`Button` controls.
struct PrimaryButtonLabel: View {
    var title: String
    var systemImage: String? = nil
    var enabled = true
    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.body.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .foregroundStyle(enabled ? Theme.onAccent : Theme.textTertiary)
        .background(enabled ? Theme.accent : Theme.surfaceRaised, in: Capsule())
    }
}

/// Full-width secondary action: soft grey pill with a hairline (the web's `pillSoft`).
struct SecondaryButtonLabel: View {
    var title: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.body.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }
}
