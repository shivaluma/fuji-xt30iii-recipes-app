import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showCompare = false
    @State private var showSave = false
    @State private var showPhotoLibrary = false
    @State private var splitEnabled = false
    @State private var showOriginal = false
    @State private var exportURL: URL?
    @State private var importing = false

    var body: some View {
        let studio = env.studio
        NavigationStack {
            VStack(spacing: 12) {
                header
                PreviewCanvas(
                    processed: studio.displayedPreview,
                    original: studio.original,
                    originalLabel: studio.asset?.baseLabel ?? "Original",
                    showHistogram: env.settings.showHistogram,
                    histogram: studio.displayMode == .approximate ? studio.histogram : nil,
                    isRendering: studio.isRendering || importing || studio.isLoadingPhoto,
                    staleCamera: studio.displayMode == .camera && studio.cameraPreviewIsStale,
                    splitEnabled: $splitEnabled,
                    forceOriginal: showOriginal)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                    .overlay(alignment: .center) { emptyState }

                controls
                    .frame(maxHeight: 390)
            }
            .background(Theme.background)
            .hiddenNavigationBar()
            .photosPicker(isPresented: $showPhotoLibrary, selection: $pickerItem, matching: .images, photoLibrary: .shared())
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .rawImage]) { result in
                if case .success(let url) = result { importFile(url) }
            }
            .onChange(of: pickerItem) { _, item in if let item { importPhotosItem(item) } }
            .sheet(isPresented: $showCompare) { CompareGridView() }
            .sheet(isPresented: $showSave) { SaveRecipeSheet() }
            .sheet(item: Binding(get: { exportURL.map(IdentifiedURL.init) }, set: { exportURL = $0?.url })) { item in
                ExportSheet(url: item.url)
            }
            .alert("Studio", isPresented: Binding(get: { studio.errorMessage != nil }, set: { if !$0 { studio.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(studio.errorMessage ?? "")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            photoMenu
            VStack(alignment: .leading, spacing: 2) {
                Text(env.studio.recipe.name + (env.studio.isDirty ? " •" : ""))
                    .font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("Tune · \(env.studio.recipe.filmSimulation.shortName)")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            CircleIconButton(systemName: splitEnabled ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                             tint: splitEnabled ? Theme.accent : Theme.textPrimary, size: 44,
                             accessibilityLabel: splitEnabled ? "Hide before and after split" : "Show before and after split") {
                splitEnabled.toggle()
            }
            CircleIconButton(systemName: showOriginal ? "eye.slash" : "eye",
                             tint: showOriginal ? Theme.accent : Theme.textPrimary, size: 44,
                             accessibilityLabel: showOriginal ? "Show recipe preview" : "Show original") {
                showOriginal.toggle()
            }
            .accessibilityIdentifier("toggleOriginal")
            recipeMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var photoMenu: some View {
        Menu {
            Button("Photo Library", systemImage: "photo") { showPhotoLibrary = true }
            Button("Files (JPEG, HEIF, RAF)", systemImage: "folder") { showFileImporter = true }
            if !env.library.assets.isEmpty {
                Section("Recent") {
                    ForEach(env.library.assets.prefix(8)) { a in
                        Button(a.originalFileName ?? "Photo") { Task { await env.studio.select(a) } }
                    }
                }
            }
        } label: {
            CircleIconLabel(systemName: "photo.badge.plus", size: 44)
        }
        .accessibilityLabel("Choose photo")
        .accessibilityIdentifier("photoMenu")
    }

    private var recipeMenu: some View {
        Menu {
            Button("Save as New Recipe…", systemImage: "plus.square.on.square") { showSave = true }
            if env.studio.canSaveInPlace {
                Button("Save Changes", systemImage: "square.and.arrow.down") { env.studio.saveChanges() }
                    .disabled(!env.studio.isDirty)
            }
            Button("Revert", systemImage: "arrow.uturn.backward") { env.studio.revert() }
                .disabled(!env.studio.isDirty)
            Divider()
            Button("Compare Recipes", systemImage: "square.grid.2x2") { showCompare = true }
                .disabled(env.studio.asset == nil)
            Button("Export Approximate JPEG", systemImage: "square.and.arrow.up") {
                Task { exportURL = try? await env.studio.exportCurrentJPEG() }
            }
            .disabled(env.studio.asset == nil)
            Divider()
            Button("Send to Camera…", systemImage: "camera") {
                if !env.library.isSaved(env.studio.recipe.id) || env.studio.isDirty { showSave = true; return }
                env.router.pendingSendRecipeID = env.studio.recipe.id
                env.router.tab = .camera
            }
        } label: {
            CircleIconLabel(systemName: "ellipsis", size: 44)
        }
        .accessibilityLabel("Recipe actions")
        .accessibilityIdentifier("recipeMenu")
    }

    @ViewBuilder private var emptyState: some View {
        if env.studio.asset == nil, !env.studio.isLoadingPhoto {
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44)).foregroundStyle(Theme.textSecondary)
                Text("Choose a photo to preview recipes").foregroundStyle(Theme.textSecondary)
                PrimaryButton(title: "Choose Photo", systemImage: "photo") { showPhotoLibrary = true }
                    .frame(width: 220)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var studio = env.studio
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                modeBar.padding(.horizontal, 16)
                simulationStrip
                TunePanel(settings: $studio.recipe.settings, hapticsEnabled: env.settings.hapticsEnabled)
                recipeCarousel
                Text("Previews are approximate on-device renderings by FilmLab, not Fujifilm's imaging engine. Nothing is sent to the camera from Studio unless you choose Render with Camera.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.vertical, 8)
            .padding(.bottom, 96) // room for the floating tab bar
        }
    }

    private var modeBar: some View {
        @Bindable var studio = env.studio
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    modeSegment("Approximate", .approximate, enabled: true)
                    modeSegment(env.camera.isDemo ? "Camera (Demo)" : "Camera", .camera, enabled: studio.cameraPreview != nil)
                }
                .padding(4)
                .background(Theme.surface, in: Capsule())
                .accessibilityIdentifier("renderModePicker")
                Spacer(minLength: 0)
                cameraButton
            }
            if case .failed(let m) = studio.cameraRenderState {
                Text(m).font(.caption2).foregroundStyle(Theme.danger).lineLimit(3)
            }
        }
    }

    private func modeSegment(_ title: String, _ mode: StudioModel.DisplayMode, enabled: Bool) -> some View {
        let selected = env.studio.displayMode == mode
        return Button { env.studio.displayMode = mode } label: {
            Text(title).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Theme.onAccent : (enabled ? Theme.textPrimary : Theme.textTertiary))
                .background(selected ? Theme.accent : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var cameraButton: some View {
        let studio = env.studio
        switch studio.cameraRenderState {
        case .rendering:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.accent)
                Button("Cancel", role: .cancel) { studio.cancelCameraRender() }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
        case .failed(let message):
            Button("Retry") { studio.renderWithCamera() }
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                .accessibilityHint(message)
        case .idle:
            let enabled = studio.cameraAvailability.isUsable && studio.asset != nil
            Button { studio.renderWithCamera() } label: {
                Label("Render with Camera", systemImage: "camera.aperture")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(enabled ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!enabled)
            .accessibilityIdentifier("renderWithCamera")
            .accessibilityHint(studio.cameraAvailability.message)
        }
    }

    private var simulationStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FILM SIMULATION").font(Theme.Font.eyebrow).tracking(1.2).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.gutter)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CameraProfile.xt30III.filmSimulations) { sim in
                            Button {
                                env.studio.setFilmSimulation(sim)
                            } label: {
                                SimulationChip(sim: sim, selected: env.studio.recipe.filmSimulation == sim)
                            }
                            .buttonStyle(PressScaleStyle())
                            .id(sim)
                            .accessibilityIdentifier("sim-\(sim.rawValue)")
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .onAppear { proxy.scrollTo(env.studio.recipe.filmSimulation, anchor: .center) }
            }
        }
    }

    private var recipeCarousel: some View {
        let recipes = env.library.recipes + env.library.catalog.filter { !env.library.isSaved($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recipes", subtitle: "Tap to preview on this photo",
                          actionTitle: "Compare", action: { showCompare = true })
                .accessibilityIdentifier("openCompare")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recipes) { r in
                        let selected = env.studio.baseRecipeID == r.id
                        Button { env.studio.load(r) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Group {
                                    if let t = env.thumbnails.thumbnail(for: r) { CGImageView(image: t, contentMode: .fill) } else { Theme.swatch(for: r.filmSimulation) }
                                }
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                                    .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2.5 : 1))
                                .onAppear { env.thumbnails.request(r) }
                                Text(r.name).font(.footnote.weight(.semibold)).lineLimit(1).frame(width: 112, alignment: .leading)
                                    .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                            }
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Recipe \(r.name), \(r.filmSimulation.displayName)")
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    // MARK: Import

    private func importPhotosItem(_ item: PhotosPickerItem) {
        importing = true
        let importer = env.library.importer
        Task {
            defer { importing = false; pickerItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportError.unreadable }
                let type = item.supportedContentTypes.first
                let asset = try await Task.detached(priority: .userInitiated) {
                    try importer.importData(data, fileName: nil, typeHint: type, source: .photos)
                }.value
                await env.studio.select(env.library.addAsset(asset))
            } catch {
                env.studio.errorMessage = error.localizedDescription
            }
        }
    }

    private func importFile(_ url: URL) {
        importing = true
        let importer = env.library.importer
        Task {
            defer { importing = false }
            do {
                let asset = try await Task.detached(priority: .userInitiated) { try importer.importFile(at: url) }.value
                await env.studio.select(env.library.addAsset(asset))
            } catch {
                env.studio.errorMessage = error.localizedDescription
            }
        }
    }
}

struct IdentifiedURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

struct ExportSheet: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(Theme.textSecondary)
                Text("Approximate preview export").font(.headline)
                Text("This JPEG was rendered by FilmLab's on-device approximation, not by the camera. The original photo is unchanged.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
                ShareLink(item: url) {
                    Label("Share JPEG", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                }
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
