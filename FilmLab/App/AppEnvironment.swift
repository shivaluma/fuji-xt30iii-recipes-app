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
    let webFeed: WebRecipeFeed
    /// Bluetooth LE link to the camera: discovery, pairing, clock/location sync, remote shutter.
    let bluetooth: FujiBluetooth
    let location = PhoneLocation()
    /// Wi‑Fi photo import (Camera tab › Import Photos).
    let wifiImport: WiFiImport
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init(paths: AppPaths, defaults: UserDefaults) {
        self.paths = paths
        settings = AppSettings(defaults: defaults)
        library = LibraryStore(paths: paths)
        renderer = OfflinePreviewRenderer(diskCacheDirectory: paths.previewCache)
        camera = CameraController(settings: settings, backupStore: CameraBackupStore(directory: paths.backups))
        studio = StudioModel(renderer: renderer, library: library,
                             cameraRenderService: UnvalidatedCameraRenderService(isCameraConnected: { false }))
        thumbnails = ThumbnailService(renderer: renderer, library: library)
        bluetooth = FujiBluetooth(defaults: defaults)
        bluetooth.locationProvider = { [location] in location.isSharing ? location.latest : nil }
        if settings.shareLocationWithCamera { location.setSharing(true) }
        wifiImport = WiFiImport(bluetooth: bluetooth, cacheDirectory: paths.caches,
                                ledgerFile: paths.root.appendingPathComponent("camera-imports.json"),
                                savesToPhotos: !ProcessInfo.processInfo.arguments.contains("-uiTesting"))
        webFeed = WebRecipeFeed(baseURL: settings.webFeedBaseURL, cacheDirectory: paths.caches)
        // UI tests stay offline: they pass the catalogue as JSON in the launch environment.
        if isUITesting, let json = ProcessInfo.processInfo.environment["FILMLAB_WEB_RECIPES_JSON"] {
            webFeed.useSnapshot(Data(json.utf8))
        }
        library.webRecipes = webFeed.recipes
    }

    /// Loads the recipe catalogue from the FilmLab website (the app ships none of its own).
    func refreshWebRecipes() async {
        if !isUITesting { await webFeed.refresh(baseURL: settings.webFeedBaseURL) }
        library.webRecipes = webFeed.recipes
        studio.adoptWebDefaults(webFeed.recipes)
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

    /// First-launch setup: sample photos, with Mt Fuji as the thumbnail and default Studio photo.
    func bootstrap() async {
        library.ensureDemoAssets()
        let demos = library.assets.filter { $0.source == .demo }
        let reference = demos.first { $0.originalFileName == DemoImageFactory.samplePhotoFileName } ?? demos.first ?? library.assets.first
        thumbnails.referenceAsset = reference
        if studio.asset == nil, let first = reference ?? library.assets.first {
            await studio.select(first)
        }
        // Cached web recipes are usable right away; the refresh then brings the latest.
        studio.adoptWebDefaults(webFeed.recipes)
        Task { await refreshWebRecipes() }
        if ProcessInfo.processInfo.arguments.contains("-demoCamera") {
            await camera.connectDemo()
            cameraModeChanged()
        }
    }

    /// Looks for a plugged-in USB camera (Camera tab, app foreground). UI tests stay offline.
    func autoDetectCamera() async {
        guard !isUITesting else { return }
        await camera.autoDetect()
    }

    func setLocationSharing(_ on: Bool) {
        settings.shareLocationWithCamera = on
        location.setSharing(on)
    }

    /// Bluetooth listening while the Camera tab is on screen (an open link stays connected).
    func setBluetoothListening(_ on: Bool) {
        guard !isUITesting else { return }
        if on { bluetooth.start() } else { bluetooth.stop() }
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
        // Native tab bar: Liquid Glass on iOS 26+, collapsing while content scrolls.
        TabView(selection: $router.tab) {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "sparkles") }
                .tag(AppTab.explore)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)
            StudioView()
                .tabItem { Label("Studio", systemImage: "camera.filters") }
                .tag(AppTab.studio)
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera") }
                .tag(AppTab.camera)
        }
        .minimizingTabBar()
        .tint(Theme.accent)
        .sensoryFeedback(.selection, trigger: router.tab)
        .task { await env.bootstrap() }
        .onChange(of: env.camera.mode) { _, _ in env.cameraModeChanged() }
        .onChange(of: env.camera.state) { _, _ in Task { await env.studio.refreshCameraAvailability() } }
    }
}
