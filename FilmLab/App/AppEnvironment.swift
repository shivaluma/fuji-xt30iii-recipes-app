import Foundation
import Observation
import SwiftUI
import CoreGraphics

enum AppTab: String, Hashable, CaseIterable {
    case explore, library, studio, camera
}

@Observable
@MainActor
final class AppRouter {
    var tab: AppTab = .studio
    /// Recipe the Camera tab should offer to send (set from Library/Studio "Send to Camera").
    var pendingSendRecipeID: UUID?
}

/// Renders recipe thumbnails on a reference photo for Explore/Library cards.
@Observable
@MainActor
final class ThumbnailService {
    private let renderer: OfflinePreviewRenderer
    private(set) var images: [String: CGImage] = [:]
    private var inFlight: Set<String> = []
    var referenceAsset: PhotoAsset?
    private let library: LibraryStore

    init(renderer: OfflinePreviewRenderer, library: LibraryStore) {
        self.renderer = renderer
        self.library = library
    }

    private func key(_ r: FilmRecipe) -> String { "\(referenceAsset?.fingerprint ?? "-")|\(r.settings.fingerprint)" }

    func thumbnail(for recipe: FilmRecipe) -> CGImage? { images[key(recipe)] }

    func request(_ recipe: FilmRecipe) {
        guard let asset = referenceAsset else { return }
        let k = key(recipe)
        guard images[k] == nil, !inFlight.contains(k) else { return }
        inFlight.insert(k)
        let url = library.importer.url(for: asset)
        Task { [renderer] in
            defer { self.inFlight.remove(k) }
            try? await renderer.loadSource(asset: asset, url: url)
            if let r = try? await renderer.render(fingerprint: asset.fingerprint, settings: recipe.settings, longEdge: 360) {
                self.images[k] = r.image
            }
        }
    }
}

/// Dependency container. `live()` for the app, `uiTesting()` for UI tests (temp storage).
@Observable
@MainActor
final class AppEnvironment {
    let paths: AppPaths
    let settings: AppSettings
    let library: LibraryStore
    let renderer: OfflinePreviewRenderer
    let camera: CameraController
    let studio: StudioModel
    let router = AppRouter()
    let thumbnails: ThumbnailService

    init(paths: AppPaths, defaults: UserDefaults) {
        self.paths = paths
        settings = AppSettings(defaults: defaults)
        library = LibraryStore(paths: paths)
        renderer = OfflinePreviewRenderer(diskCacheDirectory: paths.previewCache)
        camera = CameraController(settings: settings, backupStore: CameraBackupStore(directory: paths.backups))
        studio = StudioModel(renderer: renderer, library: library,
                             cameraRenderService: UnvalidatedCameraRenderService(isCameraConnected: { false }))
        thumbnails = ThumbnailService(renderer: renderer, library: library)
    }

    static func live() -> AppEnvironment {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTesting") {
            let suite = "FilmLab.uiTesting"
            UserDefaults().removePersistentDomain(forName: suite)
            return AppEnvironment(paths: .temporary(), defaults: UserDefaults(suiteName: suite) ?? .standard)
        }
        return AppEnvironment(paths: .live(), defaults: .standard)
    }

    /// First-launch setup: synthetic demo photos and a default Studio photo.
    func bootstrap() async {
        library.ensureDemoAssets()
        let reference = library.assets.first { $0.source == .demo } ?? library.assets.first
        thumbnails.referenceAsset = reference
        if studio.asset == nil, let first = library.assets.first {
            await studio.select(first)
        }
        if studio.compareRecipeIDs.isEmpty {
            studio.setCompare(Array(StarterRecipes.all.prefix(4).map(\.id)))
        }
        if ProcessInfo.processInfo.arguments.contains("-demoCamera") {
            await camera.connectDemo()
            cameraModeChanged()
        }
    }

    /// Keeps the Studio's camera render service in sync with the connection mode.
    func cameraModeChanged() {
        switch camera.mode {
        case .demo:
            studio.cameraRenderService = DemoCameraRenderService(renderer: renderer)
        case .usb, .none:
            let cam = camera
            studio.cameraRenderService = UnvalidatedCameraRenderService(isCameraConnected: { @MainActor in cam.transport != nil })
        }
        Task { await studio.refreshCameraAvailability() }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.tab) {
            ExploreView().hiddenSystemTabBar().tag(AppTab.explore)
            LibraryView().hiddenSystemTabBar().tag(AppTab.library)
            StudioView().hiddenSystemTabBar().tag(AppTab.studio)
            CameraView().hiddenSystemTabBar().tag(AppTab.camera)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $router.tab)
                .padding(.bottom, 4)
        }
        .background(Theme.background)
        .tint(Theme.accent)
        .preferredColorScheme(.light)
        .task { await env.bootstrap() }
        .onChange(of: env.camera.mode) { _, _ in env.cameraModeChanged() }
        .onChange(of: env.camera.state) { _, _ in Task { await env.studio.refreshCameraAvailability() } }
    }
}

/// Extra bottom space so scrolling content can clear the floating tab bar.
extension View {
    func floatingTabBarInset() -> some View {
        safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
    }
}
