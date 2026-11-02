import SwiftUI

/// FilmLab design tokens — the same light, neutral, editorial system as the website
/// (web/src/app/globals.css). Photos carry the colour; the UI stays quiet: white page, warm grey
/// panels, ink-black pills for primary actions, light display type with tight tracking.
enum Theme {
    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    // Surfaces
    static let background = Color.white                 // --fl-background
    static let surface = hex(0xf3f3f1)                    // --fl-surface: soft panels, chips, inputs
    static let surfaceRaised = hex(0xe8e8e5)              // --fl-surface-raised: pressed / nested
    /// Page behind grouped lists and forms, so their white rows read as cards.
    static let groupedBackground = hex(0xf3f3f1)
    static let hairline = hex(0xe6e6e3)                   // --fl-hairline
    /// Outline for white chips: a touch darker than hairline so the pill reads on a white page.
    static let chipStroke = hex(0xdcdcd8)

    // Text
    static let textPrimary = hex(0x0c0c0c)                // --fl-text
    static let textSecondary = hex(0x6a6a67)
    static let textTertiary = hex(0x9b9b97)

    /// Primary actions and selection are ink-black, as on the web.
    static let accent = hex(0x0c0c0c)
    static let accentMuted = hex(0xf3f3f1)
    static let onAccent = Color.white

    // Status (tuned for a light page)
    static let approximate = hex(0x5b7fa6)
    static let authentic = hex(0x2f7d55)
    static let demo = hex(0x8a7bb8)
    static let warning = hex(0xb7791f)
    static let danger = hex(0xcf3f3a)

    // Pills laid over photos: white label pill / black tag pill.
    static let photoPill = Color.white.opacity(0.92)
    static let photoPillText = Color.black
    static let photoTag = Color.black.opacity(0.72)

    static let corner: CGFloat = 24        // --fl-radius-card
    static let cornerSmall: CGFloat = 16   // --fl-radius-small
    static let spacing: CGFloat = 12
    static let gutter: CGFloat = 20        // screen side padding
    static let sectionSpacing: CGFloat = 44

    /// SF Pro stands in for Inter / Inter Tight: regular-weight display sizes with negative tracking.
    enum Font {
        static let screenTitle = SwiftUI.Font.system(size: 52, weight: .regular)
        static let sectionTitle = SwiftUI.Font.system(size: 32, weight: .regular)
        static let sectionSubtitle = SwiftUI.Font.subheadline
        static let cardTitle = SwiftUI.Font.system(size: 20, weight: .regular)
        static let eyebrow = SwiftUI.Font.caption.weight(.medium)
        static let wordmark = SwiftUI.Font.system(size: 15, weight: .semibold)
    }

    /// Letter-spacing in points for the display sizes above (≈ the web's em values).
    enum Tracking {
        static let screenTitle: CGFloat = -2.6     // -0.05em
        static let sectionTitle: CGFloat = -1.5
        static let cardTitle: CGFloat = -0.6       // -0.03em
        static let eyebrow: CGFloat = 0.8          // uppercase labels: +0.06em
    }

    static func color(for fidelity: PreviewFidelity) -> Color {
        switch fidelity {
        case .approximateOnDevice: approximate
        case .demoSimulatedCamera: demo
        case .authenticCamera: authentic
        }
    }

    /// Colour swatch per simulation for compact pickers (FilmLab's own palette).
    static func swatch(for sim: FilmSimulation) -> LinearGradient {
        let colors: [Color]
        switch sim {
        case .provia: colors = [.init(red: 0.3, green: 0.55, blue: 0.85), .init(red: 0.9, green: 0.85, blue: 0.7)]
        case .velvia: colors = [.init(red: 0.1, green: 0.6, blue: 0.3), .init(red: 0.95, green: 0.3, blue: 0.2)]
        case .astia: colors = [.init(red: 0.85, green: 0.7, blue: 0.65), .init(red: 0.6, green: 0.75, blue: 0.9)]
        case .classicChrome: colors = [.init(red: 0.4, green: 0.48, blue: 0.5), .init(red: 0.75, green: 0.65, blue: 0.5)]
        case .realaAce: colors = [.init(red: 0.85, green: 0.75, blue: 0.6), .init(red: 0.35, green: 0.6, blue: 0.75)]
        case .proNegHi: colors = [.init(red: 0.85, green: 0.65, blue: 0.55), .init(red: 0.45, green: 0.5, blue: 0.6)]
        case .proNegStd: colors = [.init(red: 0.75, green: 0.65, blue: 0.6), .init(red: 0.55, green: 0.58, blue: 0.62)]
        case .classicNeg: colors = [.init(red: 0.25, green: 0.45, blue: 0.4), .init(red: 0.9, green: 0.6, blue: 0.4)]
        case .nostalgicNeg: colors = [.init(red: 0.95, green: 0.7, blue: 0.4), .init(red: 0.6, green: 0.35, blue: 0.25)]
        case .eterna: colors = [.init(red: 0.25, green: 0.38, blue: 0.4), .init(red: 0.55, green: 0.5, blue: 0.45)]
        case .eternaBleachBypass: colors = [.init(red: 0.3, green: 0.32, blue: 0.33), .init(red: 0.7, green: 0.7, blue: 0.66)]
        case .sepia: colors = [.init(red: 0.45, green: 0.32, blue: 0.2), .init(red: 0.9, green: 0.8, blue: 0.62)]
        default: colors = [.init(white: 0.12), .init(white: 0.85)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Platform shims (keep feature code free of #if)

extension View {
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Light navigation bar that blends into the page until content scrolls under it.
    @ViewBuilder func themedNavigationBar() -> some View {
        #if os(iOS)
        self.toolbarColorScheme(.light, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Grey page behind a Form so its white rows read as cards (same as `groupedListStyle`).
    func formPage() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.groupedBackground)
    }

    /// Small uppercase tracked label, like the web's nav links and eyebrows.
    func eyebrowStyle(_ color: Color = Theme.textSecondary) -> some View {
        self.font(Theme.Font.eyebrow).textCase(.uppercase).tracking(Theme.Tracking.eyebrow).foregroundStyle(color)
    }

    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.groupedBackground)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) } // clear the floating tab bar
        #else
        self.listStyle(.inset).scrollContentBackground(.hidden).background(Theme.groupedBackground)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        #endif
    }

    func cardStyle() -> some View {
        self.padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    /// Hides the system navigation bar on root screens that draw their own `ScreenHeader`.
    @ViewBuilder func hiddenNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Hides the system tab bar; RootView draws `FloatingTabBar` instead.
    @ViewBuilder func hiddenSystemTabBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }
}
