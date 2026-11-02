import SwiftUI

/// FilmLab design tokens: dark charcoal surfaces, warm accent, crisp type. Original branding.
enum Theme {
    // Surfaces: true black canvas, layered charcoal cards.
    static let background = Color.black
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.115)        // cards, chips
    static let surfaceRaised = Color(red: 0.17, green: 0.17, blue: 0.18)   // rows inside cards, circle buttons
    static let hairline = Color.white.opacity(0.09)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    /// Primary accent: teal. Used for selection, links, and the main call to action.
    static let accent = Color(red: 0.20, green: 0.65, blue: 0.57)
    static let accentMuted = Color(red: 0.20, green: 0.65, blue: 0.57).opacity(0.18)
    static let onAccent = Color.black
    static let approximate = Color(red: 0.55, green: 0.7, blue: 0.95)
    static let authentic = Color(red: 0.36, green: 0.82, blue: 0.62)
    static let demo = Color(red: 0.82, green: 0.6, blue: 0.95)
    static let warning = Color(red: 0.98, green: 0.75, blue: 0.3)
    static let danger = Color(red: 0.95, green: 0.38, blue: 0.35)

    static let corner: CGFloat = 22        // large cards
    static let cornerSmall: CGFloat = 16   // rows, parameter cards
    static let spacing: CGFloat = 12
    static let gutter: CGFloat = 20        // screen side padding

    enum Font {
        static let screenTitle = SwiftUI.Font.system(size: 38, weight: .bold)
        static let sectionTitle = SwiftUI.Font.title2.weight(.bold)
        static let sectionSubtitle = SwiftUI.Font.subheadline
        static let cardTitle = SwiftUI.Font.headline.weight(.semibold)
        static let eyebrow = SwiftUI.Font.caption.weight(.semibold)
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

    @ViewBuilder func darkNavigationBar() -> some View {
        #if os(iOS)
        self.toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.background)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) } // clear the floating tab bar
        #else
        self.listStyle(.inset).scrollContentBackground(.hidden).background(Theme.background)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        #endif
    }

    func cardStyle() -> some View {
        self.padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
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
