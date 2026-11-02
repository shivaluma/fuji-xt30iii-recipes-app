import SwiftUI
import CoreGraphics

// FilmLab design system components: big bold screen titles, circular icon buttons, pill chips,
// large photo cards, parameter cards with a −/+ stepper, a destination card, and a floating
// capsule tab bar.

/// Large circular icon button used in screen headers.
struct CircleIconButton: View {
    var systemName: String
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 50
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Same look as `CircleIconButton`, for use as a `Menu` label.
struct CircleIconLabel: View {
    var systemName: String
    var tint: Color = Theme.textPrimary
    var size: CGFloat = 50
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Theme.surface, in: Circle())
            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Root-screen header: big bold title on the left, circular actions on the right.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.screenTitle).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) { trailing() }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }
}

/// Section title + subtitle + optional "See all ›" link in the accent colour.
struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.Font.sectionTitle).foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(Theme.Font.sectionSubtitle).foregroundStyle(Theme.textSecondary) }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// Large capsule chip with an emoji or SF Symbol.
struct PillChip: View {
    var emoji: String? = nil
    var systemImage: String? = nil
    var title: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let emoji { Text(emoji).font(.title3) }
                if let systemImage { Image(systemName: systemImage).font(.body.weight(.semibold)) }
                Text(title).font(.title3.weight(.semibold)).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
            .background(selected ? Theme.accentMuted : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Large rounded photo card with a glass badge on the image and title + simulation below.
struct PhotoRecipeCard: View {
    var recipe: FilmRecipe
    var thumbnail: CGImage?
    var width: CGFloat? = 260
    var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail { CGImageView(image: thumbnail, contentMode: .fill) } else { Theme.swatch(for: recipe.filmSimulation) }
                }
                .frame(width: width, height: width.map { $0 } ?? 180)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .clipped()
                // Status only (not a button): shows real library state, never invented counts.
                if saved || recipe.isFavorite {
                    HStack(spacing: 6) {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "checkmark")
                        Text(recipe.isFavorite ? "Favorite" : "In Library")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.black.opacity(0.55), in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 8) {
                    Label {
                        Text(recipe.filmSimulation.shortName).foregroundStyle(Theme.textSecondary)
                    } icon: {
                        Image(systemName: "film").foregroundStyle(Theme.accent)
                    }
                    .lineLimit(1)
                    if let g = recipe.inferredGeneration { GenerationBadge(generation: g) }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.name), \(recipe.filmSimulation.displayName)\(recipe.inferredGeneration.map { ", \($0.displayName)" } ?? "")\(saved ? ", in library" : "")")
    }
}

/// Small "X-Trans V" tag for recipe cards and detail.
struct GenerationBadge: View {
    var generation: XTransGeneration
    var body: some View {
        Text(generation.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(generation.displayName)
    }
}

/// Floating capsule tab bar. The selected item sits on a darker pill and turns teal.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    private func item(_ tab: AppTab) -> (String, String) {
        switch tab {
        case .explore: ("Explore", "sparkles")
        case .library: ("Library", "books.vertical.fill")
        case .studio: ("Studio", "camera.filters")
        case .camera: ("Camera", "camera.fill")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let (title, icon) = item(tab)
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon).font(.system(size: 21, weight: .semibold))
                        Text(title).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected { Capsule().fill(Color.black.opacity(0.55)) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Theme.surfaceRaised.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .padding(.horizontal, 16)
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
        VStack(alignment: .leading, spacing: 18) {
            Label(eyebrow, systemImage: "camera.aperture")
                .font(.subheadline.weight(.medium)).tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            Menu {
                picker()
            } label: {
                HStack(spacing: 18) {
                    Text(slot.label).font(.title.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.headline).foregroundStyle(Theme.textSecondary)
                }
                .padding(18)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            }
            .accessibilityIdentifier("slotPicker")
            Button(role: ctaRole, action: action) {
                Label(ctaTitle, systemImage: ctaIcon)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .foregroundStyle(ctaEnabled ? Theme.onAccent : Theme.textTertiary)
                    .background(ctaEnabled ? Theme.accent : Theme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!ctaEnabled)
            .accessibilityIdentifier(ctaIdentifier)
        }
        .padding(22)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Full-width primary button in the accent colour.
struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(enabled ? Theme.onAccent : Theme.textTertiary)
            .background(enabled ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}
