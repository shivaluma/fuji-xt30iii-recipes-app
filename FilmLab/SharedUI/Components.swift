import SwiftUI
import CoreGraphics

/// Always-visible label saying how a preview was produced.
struct FidelityBadge: View {
    var fidelity: PreviewFidelity
    var model: String? = nil
    var stale = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(for: fidelity)).frame(width: 7, height: 7)
            Text(fidelity.badge(model: model) + (stale ? " · outdated" : ""))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.photoPill, in: Capsule())
        .foregroundStyle(Theme.photoPillText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview type: \(fidelity.badge(model: model))\(stale ? ", outdated" : "")")
        .accessibilityIdentifier("fidelityBadge")
    }
}

struct DemoBadge: View {
    var body: some View {
        Text("DEMO")
            .font(.caption2.weight(.semibold)).tracking(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.demo.opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.demo)
            .accessibilityLabel("Demo data")
    }
}

struct ExperimentalBanner: View {
    var text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(Theme.warning)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Renders a CGImage without UIKit/AppKit types.
struct CGImageView: View {
    var image: CGImage
    var contentMode: ContentMode = .fit
    var body: some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: contentMode)
    }
}

/// Small swatch tile for a film simulation (picker items and recipe cards).
struct SimulationChip: View {
    var sim: FilmSimulation
    var selected: Bool
    var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let thumbnail {
                    CGImageView(image: thumbnail, contentMode: .fill)
                } else {
                    Theme.swatch(for: sim)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(selected ? Theme.accent : .clear, lineWidth: 1.5))
            Text(sim.shortName)
                .font(.caption2.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 74)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sim.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Histogram drawn from the actually displayed pixels.
struct HistogramView: View {
    var histogram: Histogram

    var body: some View {
        Canvas { ctx, size in
            func path(_ values: [Float]) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height))
                for (i, v) in values.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    p.addLine(to: CGPoint(x: x, y: size.height * (1 - CGFloat(v))))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                return p
            }
            ctx.fill(path(histogram.red), with: .color(.red.opacity(0.35)))
            ctx.fill(path(histogram.green), with: .color(.green.opacity(0.35)))
            ctx.fill(path(histogram.blue), with: .color(.blue.opacity(0.4)))
            ctx.stroke(path(histogram.luma), with: .color(.white.opacity(0.8)), lineWidth: 1)
        }
        .frame(width: 120, height: 48)
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Histogram. \(Int(histogram.clippedHighlights * 100)) percent highlights clipped, \(Int(histogram.clippedShadows * 100)) percent shadows clipped.")
    }
}

/// Card used in Explore/Library grids.
struct RecipeCard: View {
    var recipe: FilmRecipe
    var thumbnail: CGImage?
    var saved: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail { CGImageView(image: thumbnail, contentMode: .fill) } else { Theme.swatch(for: recipe.filmSimulation) }
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipped()
                if recipe.isFavorite {
                    PhotoPill(title: "Favorite", systemImage: "heart.fill").padding(8)
                        .accessibilityLabel("Favorite")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            Text(recipe.name).font(.body).tracking(-0.3).foregroundStyle(Theme.textPrimary).lineLimit(1)
            HStack(spacing: 4) {
                Text(recipe.filmSimulation.shortName)
                if saved { Image(systemName: "checkmark.circle.fill").accessibilityLabel("In library") }
            }
            .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct FilterChip: View {
    var title: String
    var isOn: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isOn ? Theme.accent : Theme.background, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.chipStroke, lineWidth: 1))
                .foregroundStyle(isOn ? Theme.onAccent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
