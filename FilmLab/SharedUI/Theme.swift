import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// FilmLab design tokens. Light mode keeps the website's neutral, editorial palette
/// (web/src/app/globals.css): white page, warm grey panels, ink-black for primary actions.
/// Every token adapts to Dark Mode, and chrome (tab bar, toolbars, sheets) is native, so on
/// iOS 26+ it renders as Liquid Glass.
enum Theme {
    private static func hex(_ v: UInt32) -> (Double, Double, Double) {
        (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }

    /// A colour that follows the system appearance.
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        let l = hex(light), d = hex(dark)
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }

    // Surfaces
    static let background = adaptive(0xffffff, 0x000000)         // --fl-background
    static let surface = adaptive(0xf3f3f1, 0x1c1c1e)            // --fl-surface: soft panels, inputs
    static let surfaceRaised = adaptive(0xe8e8e5, 0x2c2c2e)      // --fl-surface-raised: pressed / nested
    /// Page behind grouped lists and forms, so their rows read as cards.
    static let groupedBackground = adaptive(0xf3f3f1, 0x000000)
    static let hairline = adaptive(0xe6e6e3, 0x38383a)           // --fl-hairline
    static let chipStroke = adaptive(0xdcdcd8, 0x48484a)

    // Text
    static let textPrimary = adaptive(0x0c0c0c, 0xf5f5f3)        // --fl-text
    static let textSecondary = adaptive(0x6a6a67, 0xa1a19d)
    static let textTertiary = adaptive(0x9b9b97, 0x6e6e6a)

    /// Primary actions and selection: ink-black in light mode, paper-white in dark mode.
    static let accent = adaptive(0x0c0c0c, 0xf5f5f3)
    static let accentMuted = surface
    static let onAccent = adaptive(0xffffff, 0x0c0c0c)

    // Status
    static let approximate = adaptive(0x5b7fa6, 0x7fa3cc)
    static let authentic = adaptive(0x2f7d55, 0x4fb37f)
    static let demo = adaptive(0x8a7bb8, 0xa99bd8)
    static let warning = adaptive(0xb7791f, 0xe0a040)
    static let danger = adaptive(0xcf3f3a, 0xff6961)

    // Pills laid over photos: they sit on the image, so they don't follow the appearance.
    static let photoPill = Color.white.opacity(0.92)
    static let photoPillText = Color.black
    static let photoTag = Color.black.opacity(0.72)

    static let corner: CGFloat = 24        // --fl-radius-card
    static let cornerSmall: CGFloat = 16   // --fl-radius-small
    static let spacing: CGFloat = 12
    static let gutter: CGFloat = 20        // screen side padding
    static let sectionSpacing: CGFloat = 32

    enum Font {
        static let eyebrow = SwiftUI.Font.caption.weight(.medium)
    }

    enum Tracking {
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

    /// Native navigation bar; kept as a hook so screens share one call site.
    func themedNavigationBar() -> some View { self }

    /// System grouped page behind a Form (sheets get Liquid Glass on iOS 26+).
    func formPage() -> some View { self }

    /// Small uppercase tracked label, like the web's nav links and eyebrows.
    func eyebrowStyle(_ color: Color = Theme.textSecondary) -> some View {
        self.font(Theme.Font.eyebrow).textCase(.uppercase).tracking(Theme.Tracking.eyebrow).foregroundStyle(color)
    }

    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    func cardStyle() -> some View {
        self.padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    // MARK: Liquid Glass (iOS 26+) with pre-26 fallbacks
    // `#if compiler(>=6.2)` keeps the sources building with toolchains whose SDKs predate
    // Liquid Glass (e.g. scripts/typecheck.sh on Command Line Tools); they use the fallback.

    /// Prominent action: glass-prominent capsule on iOS 26+, bordered-prominent before.
    @ViewBuilder func primaryActionStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
        #else
        self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        #endif
    }

    /// Secondary action: glass capsule on iOS 26+, bordered before.
    @ViewBuilder func secondaryActionStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        }
        #else
        self.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        #endif
    }

    /// Selectable chip (capsule): prominent when selected.
    func chipStyle(selected: Bool) -> some View {
        modifier(GlassButtonShape(prominent: selected, shape: .capsule))
    }

    /// Glass capsule behind a label floating over a photo; thin material before iOS 26.
    @ViewBuilder func floatingCapsule(tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: Capsule())
        } else {
            self.background(tint ?? Color.clear, in: Capsule()).background(.ultraThinMaterial, in: Capsule())
        }
        #else
        self.background(tint ?? Color.clear, in: Capsule()).background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    /// Floating glass panel (e.g. a bottom action bar over a photo grid).
    @ViewBuilder func floatingPanel(cornerRadius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }

    /// Native tab bar collapses while scrolling down (iOS 26+).
    @ViewBuilder func minimizingTabBar() -> some View {
        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Secondary line under the navigation title (iOS 26+); nothing before.
    @ViewBuilder func navigationSubtitleIfAvailable(_ text: String) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.navigationSubtitle(text)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Glass button (prominent or not) on iOS 26+, bordered system button before.
struct GlassButtonShape: ViewModifier {
    var prominent: Bool
    var shape: ButtonBorderShape

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            if prominent { content.buttonStyle(.glassProminent).buttonBorderShape(shape) }
            else { content.buttonStyle(.glass).buttonBorderShape(shape) }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder private func fallback(_ content: Content) -> some View {
        if prominent { content.buttonStyle(.borderedProminent).buttonBorderShape(shape) }
        else { content.buttonStyle(.bordered).buttonBorderShape(shape) }
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
