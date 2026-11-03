import SwiftUI

/// Body shape used to draw a camera. Derived from the catalog id; FilmLab's own artwork,
/// not Fujifilm product imagery.
enum CameraBodyStyle: Sendable {
    /// Centre viewfinder hump: X-T, X-H, X-S.
    case slr
    /// Flat top with an offset viewfinder window: X100, X-E, X-Pro.
    case rangefinder
    /// Flat top, no viewfinder: X-M.
    case compact

    init(catalogID: String) {
        switch catalogID {
        case let id where id.hasPrefix("x100") || id.hasPrefix("x-e") || id.hasPrefix("x-pro"): self = .rangefinder
        case let id where id.hasPrefix("x-m"): self = .compact
        default: self = .slr
        }
    }
}

/// Front view of an X-series body: black body, silver top plate, dials and lens, with the
/// model name engraved. Vector, so it stays crisp at any size and in both appearances.
struct CameraIllustration: View {
    var model: String
    var style: CameraBodyStyle
    /// Dims the body (e.g. while searching or disconnected).
    var isActive = true

    var body: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
            .aspectRatio(1.62, contentMode: .fit)
            .saturation(isActive ? 1 : 0.2)
            .opacity(isActive ? 1 : 0.55)
            .shadow(color: .black.opacity(isActive ? 0.28 : 0.1), radius: 24, y: 16)
            .accessibilityElement()
            .accessibilityLabel("\(model) illustration")
    }

    private static let bodyBlack = Color(red: 0.11, green: 0.11, blue: 0.12)
    private static let leather = Color(red: 0.15, green: 0.15, blue: 0.16)
    private static let silverTop = Color(red: 0.88, green: 0.88, blue: 0.86)
    private static let silverBottom = Color(red: 0.66, green: 0.66, blue: 0.64)
    private static let dialDark = Color(red: 0.55, green: 0.55, blue: 0.53)

    private func silver(_ r: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Self.silverTop, Self.silverBottom]),
                        startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
            CGRect(x: w * x0, y: h * y0, width: w * (x1 - x0), height: h * (y1 - y0))
        }
        let plateTop: Double = style == .slr ? 0.24 : 0.16
        let plateBottom: Double = plateTop + 0.15

        // Dials and shutter button sit on the top plate.
        func dial(_ x0: Double, _ x1: Double, height: Double = 0.075) {
            let r = rect(x0, plateTop - height, x1, plateTop + 0.01)
            ctx.fill(Path(roundedRect: r, cornerRadius: w * 0.006), with: silver(r))
            for i in 1..<10 {   // knurling
                let x = r.minX + r.width * Double(i) / 10
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: r.minY + 1)); $0.addLine(to: CGPoint(x: x, y: r.maxY - 1)) },
                           with: .color(Self.dialDark.opacity(0.6)), lineWidth: 0.8)
            }
        }
        if style == .slr {
            dial(0.13, 0.27)
            dial(0.66, 0.76)
            dial(0.79, 0.90)
        } else {
            dial(0.60, 0.70, height: 0.06)
            dial(0.74, 0.86, height: 0.07)
        }
        let button = rect(0.70, plateTop - 0.11, 0.73, plateTop - 0.06)
        ctx.fill(Path(ellipseIn: button), with: silver(button))

        // Viewfinder hump (SLR style).
        if style == .slr {
            let hump = Path { p in
                p.move(to: CGPoint(x: w * 0.37, y: h * (plateTop + 0.02)))
                p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.05))
                p.addQuadCurve(to: CGPoint(x: w * 0.58, y: h * 0.05), control: CGPoint(x: w * 0.5, y: h * 0.02))
                p.addLine(to: CGPoint(x: w * 0.63, y: h * (plateTop + 0.02)))
                p.closeSubpath()
            }
            ctx.fill(hump, with: silver(rect(0.37, 0.03, 0.63, plateTop)))
            ctx.draw(Text("FUJIFILM").font(.system(size: w * 0.028, weight: .heavy)).tracking(w * 0.002)
                .foregroundStyle(Self.bodyBlack.opacity(0.85)), at: CGPoint(x: w * 0.5, y: h * 0.155))
        }

        // Top plate and body.
        let plate = rect(0.05, plateTop, 0.95, plateBottom)
        ctx.fill(Path(roundedRect: plate, cornerRadius: w * 0.04), with: silver(plate))
        let body = rect(0.05, plateBottom - 0.04, 0.95, 0.93)
        ctx.fill(Path(roundedRect: body, cornerRadius: w * 0.045), with: .color(Self.bodyBlack))
        // Leatherette band with a fine texture.
        let band = rect(0.05, plateBottom + 0.03, 0.95, 0.86)
        ctx.fill(Path(band), with: .color(Self.leather))
        var texture = Path()
        var y = band.minY + 3
        while y < band.maxY {
            texture.move(to: CGPoint(x: band.minX, y: y)); texture.addLine(to: CGPoint(x: band.maxX, y: y))
            y += 3
        }
        ctx.stroke(texture, with: .color(.white.opacity(0.025)), lineWidth: 1)
        // Grip.
        if style != .rangefinder {
            let grip = rect(0.80, plateBottom - 0.02, 0.95, 0.93)
            ctx.fill(Path(roundedRect: grip, cornerRadius: w * 0.04), with: .color(Color(red: 0.08, green: 0.08, blue: 0.09)))
        }
        // Rangefinder window; brand on the top plate for flat-top bodies.
        if style == .rangefinder {
            let window = rect(0.10, plateBottom + 0.02, 0.24, plateBottom + 0.13)
            ctx.fill(Path(roundedRect: window, cornerRadius: w * 0.008), with: .linearGradient(
                Gradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.55), Color(red: 0.08, green: 0.1, blue: 0.16)]),
                startPoint: CGPoint(x: window.minX, y: window.minY), endPoint: CGPoint(x: window.maxX, y: window.maxY)))
            ctx.stroke(Path(roundedRect: window, cornerRadius: w * 0.008), with: .color(Self.silverBottom), lineWidth: 2)
        }
        if style != .slr {
            ctx.draw(Text("FUJIFILM").font(.system(size: w * 0.024, weight: .heavy)).tracking(w * 0.002)
                .foregroundStyle(Self.bodyBlack.opacity(0.85)), at: CGPoint(x: w * 0.40, y: h * (plateTop + 0.075)))
        }

        // Model name, engraved on the front.
        ctx.draw(Text(model).font(.system(size: w * 0.026, weight: .semibold)).tracking(w * 0.001)
            .foregroundStyle(Self.silverTop.opacity(0.9)),
                 at: CGPoint(x: w * (style == .rangefinder ? 0.17 : 0.18), y: h * (style == .rangefinder ? 0.83 : plateBottom + 0.08)))

        // Lens: mount ring, barrel with focus knurling, glass with reflections.
        let lensCenter = CGPoint(x: w * (style == .rangefinder ? 0.55 : 0.5), y: h * 0.62)
        let outer = h * (style == .compact ? 0.27 : 0.30)
        func circle(_ r: Double) -> CGRect { CGRect(x: lensCenter.x - r, y: lensCenter.y - r, width: r * 2, height: r * 2) }
        ctx.fill(Path(ellipseIn: circle(outer * 1.04)), with: silver(circle(outer * 1.04)))
        ctx.fill(Path(ellipseIn: circle(outer)), with: .color(Color(red: 0.07, green: 0.07, blue: 0.08)))
        var knurl = Path()
        for i in 0..<72 {
            let a = CGFloat(i) / 72 * 2 * .pi
            knurl.move(to: CGPoint(x: lensCenter.x + cos(a) * outer * 0.80, y: lensCenter.y + sin(a) * outer * 0.80))
            knurl.addLine(to: CGPoint(x: lensCenter.x + cos(a) * outer * 0.95, y: lensCenter.y + sin(a) * outer * 0.95))
        }
        ctx.stroke(knurl, with: .color(.white.opacity(0.08)), lineWidth: 1.2)
        ctx.stroke(Path(ellipseIn: circle(outer * 0.76)), with: .color(.white.opacity(0.12)), lineWidth: 1.5)
        let glass = circle(outer * 0.6)
        ctx.fill(Path(ellipseIn: glass), with: .radialGradient(
            Gradient(colors: [Color(red: 0.22, green: 0.18, blue: 0.40), Color(red: 0.05, green: 0.07, blue: 0.14), .black]),
            center: CGPoint(x: lensCenter.x - outer * 0.15, y: lensCenter.y - outer * 0.18), startRadius: 0, endRadius: outer * 0.7))
        ctx.stroke(Path(ellipseIn: circle(outer * 0.42)), with: .color(Color(red: 0.4, green: 0.6, blue: 0.5).opacity(0.25)), lineWidth: 1)
        let glint = CGRect(x: lensCenter.x - outer * 0.32, y: lensCenter.y - outer * 0.36, width: outer * 0.24, height: outer * 0.14)
        ctx.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.35)))
        let glint2 = CGRect(x: lensCenter.x + outer * 0.12, y: lensCenter.y + outer * 0.16, width: outer * 0.08, height: outer * 0.05)
        ctx.fill(Path(ellipseIn: glint2), with: .color(.white.opacity(0.2)))
    }
}

/// Top of the Camera tab. Bluetooth is the primary link; once a USB cable connection identifies
/// a body (recipes install over USB), the USB card takes over.
struct CameraHeroCard: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        if env.camera.transport != nil || env.camera.identity != nil {
            USBCameraHeroCard()
        } else {
            BluetoothHeroCard()
        }
    }
}

/// USB connection: a large illustration of the connected body, its name, recipe family and live
/// status, and the primary connection actions.
struct USBCameraHeroCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let camera = env.camera
        let connected = camera.transport != nil
        // The body to draw: what's plugged in once identified, else a camera heard over
        // Bluetooth, else the user's own camera.
        let nearby = camera.identity == nil ? env.bluetooth.best : nil
        let profile = camera.identity != nil ? camera.profile : nearby?.advertisement.model?.profile ?? env.settings.myProfile
        let searching = camera.state == .searching
        let recognised: Bool = {
            if connected { return true }
            if case .profileOnly = camera.state { return true }
            return false
        }()

        VStack(spacing: 22) {
            ZStack {
                if searching { SearchPulse().padding(.horizontal, 40) }
                CameraIllustration(model: profile.modelName, style: CameraBodyStyle(catalogID: profile.catalogID), isActive: recognised)
                    .padding(.horizontal, 28)
                    .animation(.spring(duration: 0.5), value: recognised)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("\(profile.generation.displayName) · \(profile.generation.processor)")
                    .eyebrowStyle()
                Text(recognised ? profile.modelName
                     : nearby?.advertisement.model != nil ? "\(profile.modelName) nearby"
                     : searching ? "Looking for your \(profile.modelName)" : profile.modelName)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(camera.state.title).font(.subheadline.weight(.medium))
                    if camera.isDemo { DemoBadge() }
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .floatingCapsule()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cameraStatus")
                if let nearby {
                    Label(nearby.connectedToPhone ? "Bluetooth · connected to this iPhone" : "Bluetooth · \(nearby.advertisement.phase.label.lowercased())",
                          systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let id = camera.identity, connected || recognised {
                    Text("Firmware \(id.firmwareVersion ?? "unknown")").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let a = camera.activity {
                    Label(a, systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if searching {
                    Text("Plug your camera into this iPhone with a USB‑C data cable and set CONNECTION MODE to USB RAW CONV./BACKUP RESTORE. It's recognised automatically.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }

            actions
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(.snappy, value: camera.state)
    }

    private var statusColor: Color {
        switch env.camera.state {
        case .readyWritable, .readyReadOnly, .connected: Theme.authentic
        case .busy, .searching: Theme.approximate
        case .profileOnly, .permissionNeeded, .wrongMode: Theme.warning
        case .failed, .permissionDenied, .unsupportedModel: Theme.danger
        case .disconnected: Theme.textTertiary
        }
    }

    @ViewBuilder private var actions: some View {
        let camera = env.camera
        if camera.transport != nil {
            Button(role: .destructive) { Task { await camera.disconnectByUser() } } label: {
                PrimaryButtonLabel(title: "Disconnect", systemImage: "eject")
            }
            .foregroundStyle(Theme.danger)
            .secondaryActionStyle()
        } else {
            VStack(spacing: 10) {
                if case .profileOnly = camera.state, camera.profile.catalogID != env.settings.myCameraID {
                    Button { env.settings.myCameraID = camera.profile.catalogID } label: {
                        PrimaryButtonLabel(title: "Set as My Camera", systemImage: "checkmark.circle")
                    }
                    .tint(Theme.accent).foregroundStyle(Theme.onAccent)
                    .primaryActionStyle()
                }
                if camera.state != .searching {
                    Button { Task { await camera.startUSB() } } label: {
                        PrimaryButtonLabel(title: "Look for USB Camera", systemImage: "cable.connector")
                    }
                    .tint(Theme.accent).foregroundStyle(Theme.onAccent)
                    .primaryActionStyle()
                    .accessibilityIdentifier("connectUSB")
                }
                HStack(spacing: 10) {
                    Button { Task { await camera.connectDemo() } } label: {
                        PrimaryButtonLabel(title: "Demo Camera", systemImage: "sparkles")
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .secondaryActionStyle()
                    .accessibilityIdentifier("connectDemo")
                    if camera.state == .searching {
                        Button { Task { await camera.disconnectByUser() } } label: {
                            PrimaryButtonLabel(title: "Stop", systemImage: "stop.fill")
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .secondaryActionStyle()
                    }
                }
            }
        }
    }
}

/// Expanding rings behind the camera while FilmLab looks for one.
struct SearchPulse: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = min(size.width, size.height) * 0.75
                for i in 0..<3 {
                    let phase = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let r = maxR * (0.35 + 0.65 * phase)
                    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                               with: .color(Theme.approximate.opacity(0.45 * (1 - phase))), lineWidth: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
