import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// Import a recipe from a screenshot / recipe card / photo of notes, or pasted text.
/// 1) On-device OCR + parser (free, private). 2) Optional "Extract with AI" via the FilmLab web
/// backend for unusual layouts. Either way the user reviews every field before saving.
struct RecipeImportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case pick, reading(String), review, failed(String) }

    @State private var phase: Phase = .pick
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var pastedText = ""
    @State private var image: CGImage?
    @State private var draft = RecipeImportDraft()
    @State private var usedAI = false
    @State private var confirmIncompleteSave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch phase {
                    case .pick: pickView
                    case .reading(let what): readingView(what)
                    case .review: reviewView
                    case .failed(let m): failedView(m)
                    }
                }
                .padding(Theme.gutter)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .navigationTitle("Import Recipe")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in if let item { loadPhoto(item) } }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result { loadFile(url) }
            }
        }
    }

    // MARK: Pick

    private var pickView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Screenshots of recipe cards, blog posts, comments, or a photo of your notes all work. Text is read on this iPhone first.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                PrimaryButtonLabel(title: "Choose Screenshot or Photo", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("importPickPhoto")
            Button { showFiles = true } label: {
                SecondaryButtonLabel(title: "Choose from Files", systemImage: "folder")
            }
            .buttonStyle(PressScaleStyle())
            VStack(alignment: .leading, spacing: 8) {
                Text("Or paste text").eyebrowStyle()
                TextEditor(text: $pastedText)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                    .accessibilityLabel("Recipe text")
                PrimaryButton(title: "Read Text", systemImage: "text.viewfinder", enabled: !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    image = nil
                    usedAI = false
                    draft = RecipeCardParser.parse(text: pastedText)
                    phase = draft.isUsable ? .review : .failed("No film simulation found in that text.")
                }
            }
        }
    }

    private func readingView(_ what: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.accent)
            Text(what).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
            aiButton
            Button("Try Another Image or Text") { phase = .pick }.buttonStyle(.bordered)
        }
    }

    // MARK: Review

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let image {
                CGImageView(image: image).frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Label(usedAI ? "Read with AI" : "Read on this iPhone", systemImage: usedAI ? "sparkles" : "iphone")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Spacer()
                if !draft.missing.isEmpty || !draft.uncertain.isEmpty {
                    Text("\(draft.missing.count + draft.uncertain.count) to check").font(.caption).foregroundStyle(Theme.warning)
                }
            }
            VStack(spacing: 10) {
                TextField("Recipe name", text: $draft.name).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("importName")
                TextField("Credit (author / photographer)", text: Binding(get: { draft.credit ?? "" }, set: { draft.credit = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
                if let written = draft.writtenForLabel {
                    Label(written, systemImage: "camera")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("importWrittenFor")
                }
                Picker("X-Trans", selection: $draft.xTransGeneration) {
                    Text(draft.xTransGeneration == nil ? "Auto (\(draft.resolvedGeneration?.displayName ?? "unknown"))" : "Auto").tag(XTransGeneration?.none)
                    ForEach(XTransGeneration.allCases) { g in Text(g.displayName).tag(XTransGeneration?.some(g)) }
                }
                .font(.caption)
                .accessibilityIdentifier("importGeneration")
            }
            VStack(spacing: 0) {
                ForEach(RecipePropertyKey.allCases, id: \.self) { key in
                    row(key)
                    Divider().overlay(Theme.hairline)
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerSmall))
            if !draft.notes.isEmpty {
                Text("Notes: " + draft.notes.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if !draft.unrecognized.isEmpty {
                DisclosureGroup("Text not used (\(draft.unrecognized.count))") {
                    Text(draft.unrecognized.joined(separator: "\n")).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            // Blocking: values invalid on every body. The X-T30 III reference profile is a superset
            // of the catalog's features and ranges, so its errors are the "invalid anywhere" set.
            let errors = RecipeValidator(profile: .xt30III).validate(draft.settings.normalized()).filter { $0.severity == .error }
            ForEach(errors) { Label($0.message, systemImage: "xmark.octagon").font(.caption).foregroundStyle(Theme.danger) }
            if draft.isUsable {
                // Not blocking: how it fares on the user's own body.
                let profile = env.settings.myProfile
                let compat = RecipeCompatibility.evaluate(draft.settings.normalized(), on: profile)
                Label("\(compat.label) on your \(profile.modelName)", systemImage: compatIcon(compat))
                    .font(.caption.weight(.semibold)).foregroundStyle(compatColor(compat))
                if profile.catalogID != CameraProfile.xt30III.catalogID {
                    switch compat {
                    case .supported: EmptyView()
                    case .notAvailable(let why): Label(why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning)
                    case .worksWithChanges(let issues):
                        ForEach(issues) { Label($0.message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning) }
                    }
                }
            }
            ForEach(Array(draft.reviewMessages.enumerated()), id: \.offset) { _, m in
                Label(m.text, systemImage: m.isError ? "xmark.octagon" : "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(m.isError ? Theme.danger : Theme.warning)
            }
            ForEach(draft.unsupportedWarnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning) }

            PrimaryButton(title: "Preview & Adjust in Studio", systemImage: "camera.filters") {
                env.studio.load(draft.recipe())
                env.router.tab = .studio
                dismiss()
            }
            .accessibilityIdentifier("importPreview")
            Button {
                if draft.missing.isEmpty && draft.uncertain.isEmpty { save() } else { confirmIncompleteSave = true }
            } label: { Label("Save to Library", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 10) }
            .buttonStyle(.bordered)
            .disabled(!errors.isEmpty || draft.reviewMessages.contains { $0.isError })
            .confirmationDialog("Some fields need checking", isPresented: $confirmIncompleteSave, titleVisibility: .visible) {
                Button("Save Anyway") { save() }
                Button("Review in Studio") { env.studio.load(draft.recipe()); env.router.tab = .studio; dismiss() }
            } message: {
                Text("\(draft.missing.count) field(s) weren't read and \(draft.uncertain.count) are uncertain. Unread fields stay unset (the camera keeps its own value).")
            }
            if !usedAI { aiButton }
            Text("Nothing is sent to your camera. Fields marked “not read” stay unset — writing the recipe leaves the camera's value as-is unless you set them in Studio.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }

    private func row(_ key: RecipePropertyKey) -> some View {
        let s = draft.settings.normalized()
        let value = SlotDiff.display(key, s)
        let missing = draft.missing[key] != nil
        let uncertain = draft.uncertain.contains(key)
        return HStack {
            Text(key.displayName).font(.subheadline).foregroundStyle(value == "n/a" ? Theme.textTertiary : Theme.textPrimary)
            Spacer()
            if missing {
                Label("Not read — check", systemImage: "questionmark.circle").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
            } else {
                if uncertain { Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning).accessibilityLabel("Uncertain") }
                Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(draft.found.contains(key) ? Theme.accent : Theme.textTertiary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var aiButton: some View {
        if let client = env.settings.webClient {
            Button {
                Task { await runAI(client) }
            } label: {
                Label("Extract with AI", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .accessibilityHint("Sends the image or text to your FilmLab web server, which asks Claude to read it.")
            Text("For unusual layouts. The image is sent to your FilmLab server and Anthropic for this one request.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        } else {
            Text("Tip: connect your FilmLab web server in Settings to read unusual layouts with AI.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Actions

    private func save() {
        var r = draft.recipe()
        if !draft.otherSettings.isEmpty {
            r.summary = ([r.summary] + draft.otherSettings.map { "\($0.label): \($0.value)" }).filter { !$0.isEmpty }.joined(separator: " · ")
        }
        env.library.save(r)
        dismiss()
    }

    private func runAI(_ client: FilmLabWebClient) async {
        let text = image == nil ? pastedText : nil
        guard image != nil || !(text ?? "").isEmpty else { return }
        let onDevice = draft
        phase = .reading("Reading with AI…")
        do {
            draft = try await client.extract(image: image, text: text)
            if draft.name.isEmpty { draft.name = onDevice.name }
            usedAI = true
            phase = .review
        } catch {
            // Keep the on-device result if it's usable; never lose what was already read.
            if onDevice.isUsable {
                draft = onDevice
                draft.reviewMessages.append((false, "AI reading failed (\(error.localizedDescription)). Showing the on-device result."))
                phase = .review
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func read(_ data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            phase = .failed("That file isn't a readable image."); return
        }
        image = cg
        usedAI = false
        phase = .reading("Reading text on this iPhone…")
        Task {
            do {
                draft = try await RecipeImageImporter.importRecipe(from: cg)
            } catch {
                draft = RecipeImportDraft()
            }
            // On-device first (free, ~0.2 s). Escalate only when the result is incomplete.
            if draft.needsAIFallback, env.settings.autoAIExtraction, let client = env.settings.webClient {
                await runAI(client)
                return
            }
            phase = draft.isUsable ? .review : .failed("Couldn't find a film simulation in this image.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        phase = .reading("Loading image…")
        Task {
            defer { pickerItem = nil }
            if let data = try? await item.loadTransferable(type: Data.self) { read(data) } else { phase = .failed("Couldn't load that photo.") }
        }
    }

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) { read(data) } else { phase = .failed("Couldn't open that file.") }
    }
}
