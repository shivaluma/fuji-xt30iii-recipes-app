import SwiftUI

/// Full-bleed preview with pinch-zoom, pan, double-tap-to-fit, press-and-hold Original and a
/// draggable before/after split. Both sides are rendered from the same source at the same size,
/// so alignment is exact.
struct PreviewCanvas: View {
    var processed: RenderedPreview?
    var original: RenderedPreview?
    var originalLabel: String
    var showHistogram: Bool
    var histogram: Histogram?
    var isRendering: Bool
    var staleCamera: Bool
    @Binding var splitEnabled: Bool
    /// Header "eye" toggle: shows the Original until turned off (accessible alternative to hold).
    var forceOriginal = false

    @State private var pressing = false
    private var holdingOriginal: Bool { pressing || forceOriginal }
    @State private var split: CGFloat = 0.5
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background
                if let processed {
                    imageStack(processed: processed, size: geo.size)
                        .scaleEffect(zoom)
                        .offset(pan)
                        .gesture(zoomGesture.simultaneously(with: panGesture))
                        .onTapGesture(count: 2) { withAnimation(.spring(duration: 0.3)) { resetZoom() } }
                        .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 12, perform: {}, onPressingChanged: { pressing = $0 })
                        .accessibilityElement()
                        .accessibilityLabel(holdingOriginal ? originalLabel : "Preview")
                        .accessibilityHint("Touch and hold to see the \(originalLabel.lowercased()). Double-tap to fit.")
                        .accessibilityAction(named: "Show \(originalLabel)") { pressing.toggle() }
                        .accessibilityIdentifier("previewCanvas")
                } else {
                    ProgressView().tint(Theme.textSecondary)
                }
                overlays
                if splitEnabled, processed != nil, !holdingOriginal {
                    splitHandle(width: geo.size.width)
                }
            }
            .coordinateSpace(name: "canvas")
            .clipped()
        }
    }

    @ViewBuilder
    private func imageStack(processed: RenderedPreview, size: CGSize) -> some View {
        ZStack {
            CGImageView(image: processed.image)
            if let original {
                if holdingOriginal {
                    CGImageView(image: original.image)
                } else if splitEnabled {
                    CGImageView(image: original.image)
                        .mask(alignment: .leading) {
                            GeometryReader { g in
                                Rectangle().frame(width: g.size.width * split)
                            }
                        }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var overlays: some View {
        VStack {
            HStack(alignment: .top) {
                if holdingOriginal {
                    Text(originalLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(Theme.textPrimary)
                } else if let processed {
                    FidelityBadge(fidelity: processed.fidelity, model: processed.cameraModel, stale: staleCamera)
                }
                Spacer()
                if showHistogram, let histogram, !holdingOriginal { HistogramView(histogram: histogram) }
            }
            Spacer()
            HStack {
                if splitEnabled, !holdingOriginal {
                    Text(originalLabel).font(.caption2.weight(.semibold)).padding(6).background(.black.opacity(0.5), in: Capsule())
                    Spacer()
                    Text("Recipe").font(.caption2.weight(.semibold)).padding(6).background(.black.opacity(0.5), in: Capsule())
                } else {
                    Spacer()
                }
                if isRendering { ProgressView().controlSize(.small).tint(.white).padding(6) }
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private func splitHandle(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: max(0, width * split - 22))
            ZStack {
                Rectangle().fill(.white.opacity(0.9)).frame(width: 2)
                Circle().fill(.white).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.bold()).foregroundStyle(.black))
                    .shadow(radius: 3)
            }
            .frame(width: 44)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("canvas")).onChanged { v in
                split = min(max(v.location.x / max(width, 1), 0.02), 0.98)
            })
            .accessibilityElement()
            .accessibilityLabel("Before and after divider")
            .accessibilityValue("\(Int(split * 100)) percent original")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: split = min(split + 0.1, 0.98)
                case .decrement: split = max(split - 0.1, 0.02)
                @unknown default: break
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in zoom = min(max(baseZoom * v.magnification, 1), 6) }
            .onEnded { _ in baseZoom = zoom; if zoom <= 1.01 { withAnimation { resetZoom() } } }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard zoom > 1.01 else { return }
                pan = CGSize(width: basePan.width + v.translation.width, height: basePan.height + v.translation.height)
            }
            .onEnded { _ in basePan = pan }
    }

    private func resetZoom() {
        zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero
    }
}
