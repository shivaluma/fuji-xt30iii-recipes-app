import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct FilmLabApp: App {
    @State private var env = AppEnvironment.live()

    init() {
        #if os(iOS)
        // Navigation titles in the website's display style: light weight, tight tracking, ink.
        let ink = UIColor(red: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 1)
        let large: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40, weight: .regular), .kern: -1.6, .foregroundColor: ink]
        let inline: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .semibold), .kern: -0.3, .foregroundColor: ink]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        for a in [scrolled, edge] {
            a.largeTitleTextAttributes = large
            a.titleTextAttributes = inline
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = scrolled
        bar.compactAppearance = scrolled
        bar.scrollEdgeAppearance = edge
        bar.tintColor = ink
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
        }
    }
}
