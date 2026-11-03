import SwiftUI

/// Bluetooth-first hero: the camera FilmLab hears or is paired with, and what to do next.
struct BluetoothHeroCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let bt = env.bluetooth
        let nearby = bt.best
        let model = bt.paired?.model ?? nearby?.advertisement.model
        let profile = model?.profile ?? env.settings.myProfile
        let connected = bt.isConnected
        let searching = bt.isScanning && !connected && nearby == nil

        VStack(spacing: 22) {
            ZStack {
                if searching || isBusy(bt.link) { SearchPulse().padding(.horizontal, 40) }
                CameraIllustration(model: profile.modelName, style: CameraBodyStyle(catalogID: profile.catalogID), isActive: connected)
                    .padding(.horizontal, 28)
                    .animation(.spring(duration: 0.5), value: connected)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("\(profile.generation.displayName) · \(profile.generation.processor)").eyebrowStyle()
                Text(title(bt, model: model, profile: profile))
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                HStack(spacing: 8) {
                    Image(systemName: connected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(statusColor(bt))
                    Text(status(bt)).font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .floatingCapsule()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bluetoothStatus")
                if let firmware = bt.firmware, connected {
                    Text("Firmware \(firmware)").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let hint = hint(bt) {
                    Text(hint).font(.footnote).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 12)
                }
            }

            actions
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(.snappy, value: bt.link)
    }

    private func isBusy(_ link: FujiBluetooth.LinkState) -> Bool {
        switch link { case .connecting, .pairing: true; default: false }
    }

    private func title(_ bt: FujiBluetooth, model: CameraModelInfo?, profile: CameraProfile) -> String {
        switch bt.link {
        case .connected(let name): return name
        case .pairing: return "Pairing with \(profile.modelName)"
        case .connecting: return "Connecting to \(profile.modelName)"
        default: break
        }
        if bt.best?.advertisement.model != nil { return "\(profile.modelName) nearby" }
        if bt.paired != nil { return "Your \(profile.modelName)" }
        return "Looking for your \(profile.modelName)"
    }

    private func status(_ bt: FujiBluetooth) -> String {
        switch bt.availability {
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission needed"
        case .unsupported: return "Bluetooth unavailable here"
        default: break
        }
        if bt.link != .idle { return bt.link.title }
        if let s = bt.best { return s.connectedToPhone ? "Connected to this iPhone by another app" : s.advertisement.phase.label }
        return bt.isScanning ? "Searching over Bluetooth…" : "Bluetooth"
    }

    private func statusColor(_ bt: FujiBluetooth) -> Color {
        switch bt.link {
        case .connected: Theme.authentic
        case .failed: Theme.danger
        case .connecting, .pairing: Theme.approximate
        case .idle: bt.best != nil ? Theme.approximate : Theme.textTertiary
        }
    }

    private func hint(_ bt: FujiBluetooth) -> String? {
        switch bt.link {
        case .pairing: return "iOS shows a pairing code and so does the camera. If they match, confirm on both."
        case .failed(let m): return m
        case .connected: return nil
        default: break
        }
        switch bt.availability {
        case .unsupported: return "Bluetooth isn't available in the iOS Simulator. Run FilmLab on an iPhone to pair."
        case .unauthorized: return "Allow Bluetooth for FilmLab in iOS Settings."
        case .poweredOff: return "Turn on Bluetooth in Control Center."
        default: break
        }
        if bt.pairable == nil && bt.paired == nil {
            return "On the camera, open NETWORK/USB SETTING › Bluetooth/SMARTPHONE SETTING › PAIRING REGISTRATION. FilmLab finds it automatically."
        }
        if bt.paired != nil && bt.best == nil {
            return "Turn the camera on (or set CONNECT WHILE POWER OFF) and FilmLab reconnects automatically."
        }
        return nil
    }

    @ViewBuilder private var actions: some View {
        let bt = env.bluetooth
        if bt.isConnected {
            VStack(spacing: 10) {
                Button { bt.takePhoto() } label: {
                    PrimaryButtonLabel(title: "Take Photo", systemImage: "camera.shutter.button")
                }
                .tint(Theme.accent).foregroundStyle(Theme.onAccent)
                .primaryActionStyle()
                .sensoryFeedback(.impact, trigger: bt.lastShot)
                .accessibilityIdentifier("bluetoothShutter")
                Button(role: .destructive) { bt.disconnect() } label: {
                    PrimaryButtonLabel(title: "Disconnect", systemImage: "xmark.circle")
                }
                .foregroundStyle(Theme.danger)
                .secondaryActionStyle()
            }
        } else if isBusy(bt.link) {
            Button { bt.disconnect() } label: { PrimaryButtonLabel(title: "Cancel", systemImage: "xmark") }
                .foregroundStyle(Theme.textPrimary)
                .secondaryActionStyle()
        } else if let target = bt.pairable {
            Button { bt.pair(with: target) } label: {
                PrimaryButtonLabel(title: "Pair with \(target.advertisement.model?.name ?? target.advertisement.name ?? "Camera")",
                                   systemImage: "link")
            }
            .tint(Theme.accent).foregroundStyle(Theme.onAccent)
            .primaryActionStyle()
            .accessibilityIdentifier("bluetoothPair")
        } else if bt.paired != nil {
            HStack(spacing: 10) {
                Button { bt.reconnect() } label: { PrimaryButtonLabel(title: "Reconnect", systemImage: "arrow.clockwise") }
                    .tint(Theme.accent).foregroundStyle(Theme.onAccent)
                    .primaryActionStyle()
                Button(role: .destructive) { bt.forget() } label: { PrimaryButtonLabel(title: "Forget", systemImage: "trash") }
                    .foregroundStyle(Theme.textPrimary)
                    .secondaryActionStyle()
            }
        }
    }
}

/// Details for the Bluetooth link: location sharing, sync status, what travels over the air.
struct BluetoothDetailsSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showLog = false

    var body: some View {
        let bt = env.bluetooth
        Section {
            if bt.isConnected || bt.paired != nil {
                Toggle(isOn: Binding(get: { env.settings.shareLocationWithCamera }, set: { env.setLocationSharing($0) })) {
                    Label("Share location for geotags", systemImage: "location")
                }
                if env.settings.shareLocationWithCamera, env.location.status == .denied {
                    Label("Location access is off for FilmLab. Allow it in iOS Settings.", systemImage: "location.slash")
                        .foregroundStyle(Theme.warning)
                }
                LabeledContent("Clock sync", value: bt.lastClockSync.map { "Sent \($0.formatted(date: .omitted, time: .shortened))" } ?? "When the camera asks")
                LabeledContent("Location sync", value: bt.lastLocationSync.map { "Sent \($0.formatted(date: .omitted, time: .shortened))" }
                               ?? (env.settings.shareLocationWithCamera ? "When the camera asks" : "Off"))
            }
            Label("Photos travel over the camera's Wi‑Fi, not Bluetooth.", systemImage: "photo.on.rectangle")
            Label("Recipes (C1–C7) install over the USB cable. FilmLab doesn't read or write settings, backups or recipes over Bluetooth: that protocol isn't published, and a wrong guess could scramble the camera's settings.", systemImage: "cable.connector")
            if !bt.log.isEmpty {
                DisclosureGroup("Bluetooth log", isExpanded: $showLog) {
                    Text(bt.log.suffix(30).joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Bluetooth")
        } footer: {
            Text("Pairing, clock and location sync and the remote shutter follow community-reported protocols (furble, libfuji), not Fujifilm documentation, and haven't been verified on a camera by FilmLab yet. Experimental.")
        }
        .font(.footnote)
    }
}
