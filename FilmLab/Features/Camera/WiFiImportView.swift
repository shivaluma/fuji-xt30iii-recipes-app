import SwiftUI

/// Browse the camera's card over Wi‑Fi and import originals into Photos.
struct WiFiImportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var selecting = false
    @State private var selection: Set<UInt32> = []

    var body: some View {
        let wifi = env.wifiImport
        Group {
            if wifi.isConnected { browser } else { connectPanel }
        }
        .navigationTitle(wifi.isConnected ? (wifi.cameraName ?? "Camera") : "Import Photos")
        .navigationSubtitleIfAvailable(subtitle(wifi))
        .inlineNavigationTitle()
        .toolbar { toolbar }
        .animation(.snappy, value: wifi.phase)
        .sensoryFeedback(.success, trigger: wifi.importedCount)
        .onDisappear {
            // Free the camera (and its battery) when leaving, unless photos are still coming in.
            if !wifi.isTransferring { wifi.disconnect() }
        }
    }

    private func subtitle(_ wifi: WiFiImport) -> String {
        guard wifi.isConnected else { return "Over Wi‑Fi" }
        return "\(wifi.items.count) on card\(wifi.isDemo ? " · Demo" : "")"
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        let wifi = env.wifiImport
        if wifi.isConnected {
            ToolbarItem(placement: .primaryAction) {
                Button(selecting ? "Done" : "Select") {
                    selecting.toggle()
                    selection = []
                }
                .accessibilityIdentifier("wifiSelect")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Disconnect", systemImage: "wifi.slash", role: .destructive) { wifi.disconnect() }
                }
            }
        }
    }

    // MARK: Connect

    private var connectPanel: some View {
        let wifi = env.wifiImport
        let bt = env.bluetooth
        return List {
            Section {
                VStack(spacing: 16) {
                    ZStack {
                        if wifi.phase.isWorking { SearchPulse().frame(height: 150) }
                        Image(systemName: icon(wifi.phase))
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.variableColor.iterative, isActive: wifi.phase.isWorking)
                            .frame(height: 150)
                    }
                    Text(headline(wifi.phase)).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("wifiPhase")
                    Text(detail(wifi.phase)).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    if wifi.phase.isWorking {
                        Button { wifi.disconnect() } label: { PrimaryButtonLabel(title: "Cancel", systemImage: "xmark") }
                            .secondaryActionStyle()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            if !wifi.phase.isWorking {
                Section {
                    if bt.isConnected {
                        Button { wifi.connect(.bluetooth) } label: {
                            PrimaryButtonLabel(title: "Connect to \(bt.paired?.model?.name ?? "Camera")", systemImage: "bolt.horizontal.circle")
                        }
                        .primaryActionStyle()
                        .accessibilityIdentifier("wifiConnectBluetooth")
                    }
                    Button { wifi.connect(.wireless) } label: {
                        PrimaryButtonLabel(title: bt.isConnected ? "Camera's Wi‑Fi Screen Is Open" : "Connect", systemImage: "wifi")
                    }
                    .modifier(ConditionalPrimary(prominent: !bt.isConnected))
                    .accessibilityIdentifier("wifiConnectWireless")
                } footer: {
                    Text(bt.isConnected
                         ? "FilmLab turns on the camera's Wi‑Fi over Bluetooth and joins it for you."
                         : "On the camera, press PLAYBACK, then choose WIRELESS COMMUNICATION (or press the Wi‑Fi button). Pair over Bluetooth on the Camera tab to skip this next time.")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section("Why it's fast") {
                    Label("Originals, not resized copies, straight into Photos", systemImage: "photo.stack")
                    Label("Newest photos and on-screen thumbnails load first", systemImage: "clock.arrow.circlepath")
                    Label("Photos you already imported are skipped", systemImage: "checkmark.circle")
                    Label("The next photo downloads while the last one saves", systemImage: "arrow.down.circle")
                }
                .font(.subheadline)

                Section {
                    Button("Try the Demo Camera", systemImage: "sparkles") { wifi.connect(.demo) }
                        .accessibilityIdentifier("wifiDemo")
                } footer: {
                    Text("An emulated camera on this iPhone, speaking the same Wi‑Fi protocol. Its photos are samples.")
                }
            }
        }
        .groupedListStyle()
    }

    private func icon(_ phase: WiFiImport.Phase) -> String {
        switch phase {
        case .failed: "wifi.exclamationmark"
        case .wakingCamera: "antenna.radiowaves.left.and.right"
        case .waitingForApproval: "hand.tap"
        default: "wifi"
        }
    }

    private func headline(_ phase: WiFiImport.Phase) -> String {
        switch phase {
        case .idle, .browsing: "Import photos over Wi‑Fi"
        case .wakingCamera: "Turning on the camera's Wi‑Fi…"
        case .joiningNetwork: "Joining the camera's network…"
        case .connecting: "Connecting…"
        case .waitingForApproval: "Press OK on the camera"
        case .failed: "Couldn't connect"
        }
    }

    private func detail(_ phase: WiFiImport.Phase) -> String {
        switch phase {
        case .idle, .browsing: "Browse the card and copy full-size originals to Photos."
        case .wakingCamera: "Over Bluetooth."
        case .joiningNetwork(let ssid): ssid.map { "Allow joining “\($0)” if iOS asks." } ?? "Allow joining the FUJIFILM network if iOS asks."
        case .connecting: "Reaching the camera at 192.168.0.1."
        case .waitingForApproval: "The camera asks to confirm this iPhone the first time."
        case .failed(let message): message
        }
    }

    // MARK: Browser

    private var browser: some View {
        let wifi = env.wifiImport
        return ScrollView {
            if let error = wifi.transferError {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
                    .padding(.horizontal, Theme.gutter).padding(.top, 8)
            }
            if wifi.items.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "photo", description: Text("The memory card is empty."))
                    .padding(.top, 80)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                ForEach(wifi.items) { item in
                    CameraPhotoCell(item: item, selecting: selecting, selected: selection.contains(item.handle))
                        .onAppear { wifi.requestThumbnail(item.handle) }
                        .onDisappear { wifi.cancelThumbnail(item.handle) }
                        .onTapGesture {
                            guard selecting else { return }
                            if selection.contains(item.handle) { selection.remove(item.handle) } else { selection.insert(item.handle) }
                        }
                        .contextMenu {
                            Button("Import to Photos", systemImage: "square.and.arrow.down") { wifi.importSelection([item.handle]) }
                        }
                }
            }
            .accessibilityIdentifier("wifiGrid")
        }
        .safeAreaInset(edge: .bottom) { bottomBar.padding(.horizontal, Theme.gutter).padding(.bottom, 8) }
    }

    @ViewBuilder private var bottomBar: some View {
        let wifi = env.wifiImport
        VStack(spacing: 10) {
            if wifi.isTransferring {
                let current = wifi.items.compactMap { if case .downloading(let f) = $0.status { f } else { nil } }.first ?? 0
                let total = max(wifi.batchTotal, 1)
                ProgressView(value: min(1, (Double(wifi.batchDone) + current) / Double(total)))
                HStack {
                    Text("Importing \(min(wifi.batchDone + 1, total)) of \(total)").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let rate = wifi.meter?.rateLabel { Text(rate).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary) }
                    Button("Stop", role: .cancel) { wifi.cancelTransfers() }.font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("wifiProgress")
            } else if selecting {
                Button {
                    wifi.importSelection(selection)
                    selecting = false
                    selection = []
                } label: { PrimaryButtonLabel(title: selection.isEmpty ? "Select Photos" : "Import \(selection.count) to Photos", systemImage: "square.and.arrow.down") }
                .primaryActionStyle()
                .disabled(selection.isEmpty)
            } else {
                if wifi.importedCount > 0 {
                    Button { openURL(URL(string: "photos-redirect://")!) } label: {
                        Label("\(wifi.importedCount) imported · Open Photos", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("wifiImported")
                }
                Button { wifi.importNew() } label: { PrimaryButtonLabel(title: "Import New Photos", systemImage: "square.and.arrow.down.on.square") }
                    .primaryActionStyle()
                    .disabled(wifi.newItems.isEmpty)
                    .accessibilityIdentifier("wifiImportNew")
            }
        }
        .padding(14)
        .floatingPanel()
    }
}

private struct ConditionalPrimary: ViewModifier {
    var prominent: Bool
    func body(content: Content) -> some View {
        if prominent { content.primaryActionStyle() } else { content.secondaryActionStyle() }
    }
}

/// One photo on the card: camera thumbnail, file type, and import state.
private struct CameraPhotoCell: View {
    let item: WiFiImport.Item
    let selecting: Bool
    let selected: Bool

    var body: some View {
        Color(Theme.surface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumb = item.thumbnail {
                    Image(decorative: thumb, scale: 1).resizable().scaledToFill().transition(.opacity)
                } else {
                    ProgressView().controlSize(.small).opacity(0.5)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if let info = item.info, info.isRAW || info.isMovie {
                    Text(info.isRAW ? "RAW" : "MOV").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.photoTag, in: Capsule()).padding(5)
                }
            }
            .overlay(alignment: .topTrailing) { badge.padding(6) }
            .overlay {
                if case .downloading(let f) = item.status {
                    ZStack {
                        Color.black.opacity(0.35)
                        ProgressView(value: f).progressViewStyle(.circular).tint(.white)
                    }
                }
                if selecting && selected { Theme.accent.opacity(0.18) }
            }
            .opacity(item.status == .imported && !selecting ? 0.55 : 1)
            .animation(.snappy, value: item.status)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.info?.fileName ?? "Photo \(item.handle)")
            .accessibilityValue(accessibilityStatus)
            .accessibilityAddTraits(selecting && selected ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if selecting {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(selected ? Theme.accent : .white)
                .background(Circle().fill(selected ? Theme.onAccent : .black.opacity(0.25)))
        } else {
            switch item.status {
            case .imported: Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Theme.authentic)
            case .queued: Image(systemName: "clock.fill").foregroundStyle(.white)
            case .saving: Image(systemName: "arrow.down.circle.fill").foregroundStyle(.white)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.white, Theme.danger)
            case .new, .downloading: EmptyView()
            }
        }
    }

    private var accessibilityStatus: String {
        switch item.status {
        case .new: "Not imported"
        case .imported: "Imported"
        case .queued: "Waiting"
        case .downloading(let f): "Downloading, \(Int(f * 100)) percent"
        case .saving: "Saving to Photos"
        case .failed(let m): "Failed: \(m)"
        }
    }
}
