import SwiftUI

@main
struct FilmLabApp: App {
    @State private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
        }
    }
}
