import SwiftUI

@main
struct FilmLabApp: App {
    @State private var env = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    // Navigation bars use the system appearance: Liquid Glass with scroll-edge effects on
    // iOS 26+, and titles that follow Light/Dark Mode.
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .onChange(of: scenePhase) { _, phase in
                    // Back in the foreground: pick up a camera plugged in meanwhile, refresh web recipes.
                    guard phase == .active else { return }
                    Task { await env.autoDetectCamera() }
                    Task { await env.refreshWebRecipes() }
                }
        }
    }
}
