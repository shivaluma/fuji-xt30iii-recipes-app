import SwiftUI

struct CameraView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sendRecipeID: UUID?
    @State private var diagnostics: String?
    @State private var showSetInstall: RecipeSet?

    var body: some View {
        let camera = env.camera
        NavigationStack {
            List {
                Section { CameraHeroCard() }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                noticesSection
                photosSection
                BluetoothDetailsSection()
                if camera.transport == nil && camera.identity == nil { usbSection; setupGuide }
                if camera.transport != nil { slotsSection; actionsSection }
                if !camera.backups.isEmpty { backupsSection }
                Section {
                    NavigationLink("\(camera.profile.modelName) capabilities & verification status") { CapabilitiesView(profile: camera.profile) }
                    NavigationLink("Supported cameras") { SupportedCamerasView() }
                } header: {
                    Text("Camera model")
                }
                Section {
                    Button("Share Redacted Diagnostics…") {
                        Task {
                            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                            diagnostics = await camera.diagnosticsReport(appVersion: v, osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
                        }
                    }
                } footer: {
                    Text("Diagnostics include operation codes, sizes and response codes only — never photos, PTP payloads or serial numbers. Nothing is sent unless you share it.")
                }
            }
            .groupedListStyle()
            .navigationTitle("Camera")
            .task { await env.autoDetectCamera() }
            .onAppear { env.setBluetoothListening(true) }
            .onDisappear { env.setBluetoothListening(false) }
            .themedNavigationBar()
            .sheet(item: Binding(get: { sendRecipeID.map(IdentifiedUUID.init) }, set: { sendRecipeID = $0?.id })) { item in
                SendToCameraSheet(recipeID: item.id)
            }
            .sheet(item: $showSetInstall) { set in SetInstallSheet(set: set) }
            .sheet(item: Binding(get: { diagnostics.map(IdentifiedText.init) }, set: { diagnostics = $0?.text })) { d in
                NavigationStack {
                    ScrollView { Text(d.text).font(.caption.monospaced()).textSelection(.enabled).padding() }
                        .toolbar { ShareLink(item: d.text) }
                        .navigationTitle("Diagnostics")
                        .inlineNavigationTitle()
                }
            }
            .onAppear(perform: consumePendingSend)
            .onChange(of: env.router.pendingSendRecipeID) { _, _ in consumePendingSend() }
        }
    }

    private func consumePendingSend() {
        if let id = env.router.pendingSendRecipeID {
            sendRecipeID = id
            env.router.pendingSendRecipeID = nil
        }
    }

    // MARK: Sections

    /// Wi‑Fi: browse the card and import originals into Photos.
    private var photosSection: some View {
        let wifi = env.wifiImport
        return Section {
            NavigationLink {
                WiFiImportView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Photos").font(.body.weight(.semibold))
                        Text(wifi.isTransferring ? "Importing \(min(wifi.batchDone + 1, wifi.batchTotal)) of \(wifi.batchTotal)…"
                             : wifi.isConnected ? "Connected over Wi‑Fi" : "Full-size originals over Wi‑Fi, straight to Photos")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                } icon: {
                    Image(systemName: "photo.stack").foregroundStyle(Theme.accent)
                }
            }
            .accessibilityIdentifier("importPhotos")
        } header: {
            Text("Photos · Wi‑Fi")
        }
    }

    /// USB cable: the route for installing recipes into C1–C7.
    private var usbSection: some View {
        let camera = env.camera
        return Section {
            LabeledContent("Status", value: camera.state.title)
                .accessibilityIdentifier("cameraStatus")
            if camera.state != .searching {
                Button("Look for USB Camera", systemImage: "cable.connector") { Task { await camera.startUSB() } }
                    .accessibilityIdentifier("connectUSB")
            } else {
                Button("Stop Looking", systemImage: "stop.circle") { Task { await camera.disconnectByUser() } }
            }
            Button("Use Demo Camera", systemImage: "sparkles") { Task { await camera.connectDemo() } }
                .accessibilityIdentifier("connectDemo")
        } header: {
            Text("USB cable · install recipes")
        } footer: {
            Text("Reading and writing C1–C7 needs the cable. Plugged-in cameras are recognised automatically.")
        }
    }

    /// Warnings and explanations for the current connection state (the hero shows the status).
    @ViewBuilder private var noticesSection: some View {
        let camera = env.camera
        let hasNotice: Bool = {
            switch camera.state {
            case .wrongMode, .unsupportedModel, .profileOnly, .permissionDenied, .failed: return true
            default: return camera.lastError != nil || camera.mode == .usb || !camera.slotsNeedingVerification.isEmpty
            }
        }()
        if hasNotice {
            Section {
                if case .wrongMode(let m) = camera.state { Label(m, systemImage: "cable.connector").foregroundStyle(Theme.warning).font(.footnote) }
                if case .unsupportedModel(let m) = camera.state {
                    Label("\(m) isn't in FilmLab's camera list yet. Recipes still work on it, but FilmLab can't connect to it.", systemImage: "xmark.octagon").font(.footnote)
                }
                if case .profileOnly(let id) = camera.state {
                    Label("FilmLab recognises the \(id.model) (\(camera.profile.generation.displayName)) and uses its profile for checks, but reading or writing C1–C7 over USB is only offered on the X-T30 III — the one body with community reports of the protocol working. The camera was released.",
                          systemImage: "info.circle").font(.footnote)
                }
                if case .permissionDenied = camera.state {
                    Label("Camera control permission was denied. Enable it for FilmLab in iOS Settings.", systemImage: "lock").font(.footnote)
                }
                if case .failed(let m) = camera.state { Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger).font(.footnote) }
                if let e = camera.lastError { Text(e).font(.footnote).foregroundStyle(Theme.danger) }
                if camera.mode == .usb {
                    ExperimentalBanner(text: "Experimental hardware integration — not yet verified on a physical camera by FilmLab.")
                }
                if !camera.slotsNeedingVerification.isEmpty {
                    Label("Verify \(camera.slotsNeedingVerification.sorted().map(\.label).joined(separator: ", ")): last write outcome unknown. Reconnect and read.", systemImage: "questionmark.diamond")
                        .foregroundStyle(Theme.warning).font(.footnote)
                }
            }
        }
    }

    private var setupGuide: some View {
        Section("Connect with a USB cable") {
            Label("Charge the camera and use a USB-C cable that carries data (not charge-only).", systemImage: "battery.100")
            Label("Camera menu: USB POWER SUPPLY/COMM SETTING → AUTO or POWER SUPPLY OFF/COMM ON.", systemImage: "bolt.horizontal")
            Label("Camera menu: CONNECTION MODE → USB RAW CONV./BACKUP RESTORE.", systemImage: "gearshape.2")
            Label("Connect to the iPhone, turn the camera on, then tap Look for USB Camera.", systemImage: "cable.connector")
            Text("If nothing is found: try another cable, check the connection mode, and make sure the camera isn't in movie mode or asleep.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .font(.footnote)
    }

    private var slotsSection: some View {
        let camera = env.camera
        return Section {
            ForEach(CameraSlot.allCases) { slot in
                NavigationLink {
                    SlotDetailView(slot: slot)
                } label: {
                    HStack {
                        Text(slot.label).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent).frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(camera.snapshots[slot]?.name ?? "Not read").font(.body)
                            Text(camera.snapshots[slot]?.settings?.filmSimulation.displayName ?? "—")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if let s = camera.snapshots[slot], s.completeness != .complete {
                            Text(s.completeness.rawValue).font(.caption2).foregroundStyle(Theme.warning)
                        }
                    }
                }
                .accessibilityIdentifier("slot-\(slot.label)")
            }
        } header: {
            Text("Custom settings C1–C7")
        } footer: {
            Text("C1–C7 are custom setting banks. They are separate from the film simulation dial's FS1–FS3 positions, which FilmLab does not program. A film simulation saved in a C bank applies when the dial is set to C.")
        }
    }

    private var actionsSection: some View {
        let camera = env.camera
        return Section("Actions") {
            Button("Read All Slots") { Task { await camera.readAllSlots() } }
                .accessibilityIdentifier("readAllSlots")
            Button("Back Up All Slots") { Task { await camera.backupAll(reason: "Manual backup") } }
            Menu("Send a Recipe to a Slot…") {
                ForEach(env.library.recipes) { r in Button(r.name) { sendRecipeID = r.id } }
            }
            .disabled(env.library.recipes.isEmpty)
            Menu("Install a Set…") {
                ForEach(env.library.sets) { s in Button(s.name) { showSetInstall = s } }
            }
            .disabled(env.library.sets.isEmpty)
            if !camera.state.canWrite, camera.transport != nil {
                Text("Writes are disabled. Enable experimental slot writes in Library › Settings.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var backupsSection: some View {
        let camera = env.camera
        return Section("Backups (stored on this iPhone)") {
            ForEach(camera.backups.prefix(10)) { b in
                HStack {
                    VStack(alignment: .leading) {
                        Text(b.createdAt.formatted(date: .abbreviated, time: .standard)).font(.subheadline)
                        Text("\(b.camera.displayName) · \(b.reason)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let url = camera.exportURL(for: b) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Export backup")
                    }
                }
                .swipeActions { Button("Delete", role: .destructive) { camera.deleteBackup(b) } }
            }
        }
    }
}

struct IdentifiedUUID: Identifiable { var id: UUID }
struct IdentifiedText: Identifiable { var text: String; var id: String { text } }

// MARK: - Slot detail

struct SlotDetailView: View {
    @Environment(AppEnvironment.self) private var env
    var slot: CameraSlot

    var body: some View {
        let snap = env.camera.snapshots[slot]
        List {
            if let snap {
                Section {
                    LabeledContent("Name", value: snap.name)
                    LabeledContent("Read", value: snap.readAt.formatted(date: .omitted, time: .standard))
                    LabeledContent("Completeness", value: snap.completeness.rawValue)
                    if snap.camera.isDemo { DemoBadge() }
                }
                if let s = snap.settings {
                    Section("Settings") {
                        ForEach(SlotDiff.rows(before: nil, new: s)) { row in
                            LabeledContent(row.key.displayName, value: row.kind == .keepsCameraValue ? "—" : row.after)
                        }
                    }
                    Section {
                        Button("Save as Recipe in Library") {
                            let r = FilmRecipe(name: snap.name, summary: "Read from \(slot.label) on \(snap.camera.displayName)",
                                               settings: s, provenance: RecipeProvenance(kind: .cameraSlot, note: "Read \(snap.readAt.formatted())"))
                            env.library.save(r)
                        }
                        Button("Preview in Studio") {
                            env.studio.load(FilmRecipe(name: snap.name, settings: s, provenance: RecipeProvenance(kind: .cameraSlot)))
                            env.router.tab = .studio
                        }
                    }
                }
                if !snap.unknownValues.isEmpty {
                    Section {
                        ForEach(snap.unknownValues, id: \.code) { v in
                            LabeledContent(String(format: "0x%04X", v.code), value: v.bytes.hexString).font(.caption.monospaced())
                        }
                    } header: { Text("Preserved, not interpreted") } footer: {
                        Text("These values are kept byte-for-byte in backups. FilmLab never writes properties it doesn't understand.")
                    }
                }
            } else {
                Section {
                    Text("Not read yet.")
                    Button("Read \(slot.label)") { Task { await env.camera.read([slot]) } }
                }
            }
        }
        .groupedListStyle()
        .navigationTitle(slot.label)
        .inlineNavigationTitle()
    }
}

// MARK: - Capabilities

struct CapabilitiesView: View {
    var profile: CameraProfile = .xt30III
    var body: some View {
        List {
            Section("Body") {
                LabeledContent("Model", value: profile.modelName)
                LabeledContent("Recipe family", value: profile.generation.displayName)
                LabeledContent("Sensor", value: profile.sensor)
                LabeledContent("Processor", value: profile.processor)
                LabeledContent("Custom slots", value: "C1–C\(profile.customSlotCount)")
                if profile.filmSimulationDialSlots.isEmpty {
                    LabeledContent("Film simulation dial", value: "None")
                } else {
                    LabeledContent("Film simulation dial", value: profile.filmSimulationDialSlots.map(\.rawValue).joined(separator: ", ") + " (not written by FilmLab)")
                }
                LabeledContent("Feature data", value: profile.dataStatus.label)
                LabeledContent("USB slot writes", value: profile.allowsSlotWrites ? "Experimental (off by default)" : "Not offered")
            }
            Section("Film simulations (\(profile.filmSimulations.count))") {
                Text(profile.filmSimulations.map(\.displayName).joined(separator: " · ")).font(.footnote)
                let missing = FilmSimulation.allCases.filter { !profile.filmSimulations.contains($0) }
                if !missing.isEmpty {
                    Text("Not available: " + missing.map(\.displayName).joined(separator: ", ")).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Section("Properties") {
                ForEach(RecipePropertyKey.allCases, id: \.self) { key in
                    if let c = profile.capability(key) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(key.displayName).font(.subheadline.weight(.medium))
                                    .foregroundStyle(c.isSupported ? Theme.textPrimary : Theme.textTertiary)
                                Spacer()
                                if !c.isSupported { Text("Not available").font(.caption).foregroundStyle(Theme.textTertiary) }
                                if let r = c.range { Text("\(RecipeValidator.format(r.min))…\(RecipeValidator.format(r.max))").font(.caption.monospaced()) }
                            }
                            Text("Values: \(c.valuesStatus.label)").font(.caption2)
                            Text("USB read/write: \(c.ptpWriteStatus.label)").font(.caption2).foregroundStyle(Theme.warning)
                            if let n = c.note { Text(n).font(.caption2).foregroundStyle(Theme.textSecondary) }
                        }
                    }
                }
            }
            if !profile.knownQuirks.isEmpty {
                Section("Known quirks & constraints") {
                    ForEach(profile.knownQuirks, id: \.self) { Text($0).font(.footnote) }
                }
            }
        }
        .groupedListStyle()
        .navigationTitle(profile.modelName)
        .inlineNavigationTitle()
    }
}

/// Every body in the catalog, grouped by recipe family.
struct SupportedCamerasView: View {
    var body: some View {
        List {
            ForEach(CameraCatalog.grouped(), id: \.generation) { group in
                Section {
                    ForEach(group.cameras) { cam in
                        NavigationLink { CapabilitiesView(profile: cam.profile) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cam.name).font(.body.weight(.medium))
                                Text("\(cam.sensor) · \(cam.processor)").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } header: {
                    Text(group.generation.displayName)
                } footer: {
                    Text(group.generation == .v
                         ? "X-Processor 5 bodies, including the X-T30 III, X-S20 and X-M5, which pair it with an X-Trans CMOS 4 sensor."
                         : "X-Processor 4 bodies. X-Trans IV recipes also run on X-Trans V cameras.")
                }
            }
            Section {
                Text("Only the X-T30 III's ranges are checked against its manual. The other bodies' feature support is community-reported and may change with firmware. USB slot access is offered only on the X-T30 III.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .groupedListStyle()
        .navigationTitle("Supported cameras")
        .inlineNavigationTitle()
    }
}
