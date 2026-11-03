import Foundation
import ImageCaptureCore

/// Real-hardware PTP channel backed by `ICCameraDevice.requestSendPTPCommand(_:outData:completion:)`
/// (iOS 13+, per Apple's SDK headers).
///
/// Wire format (from Apple's PTPPassThrough sample, see docs/research.md §5):
///  - command: the full PTP command container (ImageCaptureCore ignores our transaction ID);
///  - outData: the raw data-phase payload, no container header;
///  - completion `responseData`: the data-in payload (no header);
///  - completion `ptpResponseData`: the response container INCLUDING its 12-byte header.
/// ⚠️ This mapping must be confirmed on a real iPhone + X-T30 III (docs/device-test-matrix.md).
///
/// Main-actor isolated: `ICCameraDevice` is not `Sendable`, so all access happens on the main
/// actor. The call is asynchronous and never blocks the main thread.
@MainActor
final class ImageCapturePTPChannel: PTPCommandChannel {
    nonisolated var echoesTransactionIDs: Bool { false }
    /// Set if the completion buffers arrived in the opposite order to Apple's sample (diagnostic).
    static var observedSwappedBuffers = false
    private let device: ICCameraDevice
    private var isClosed = false

    init(device: ICCameraDevice) {
        self.device = device
    }

    func perform(_ command: PTPContainer, outData: Data?, timeout: Duration) async throws -> PTPTransactionResult {
        guard !isClosed else { throw PTPError.disconnected }
        guard device.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
            throw PTPError.transport("This device does not accept PTP pass-through commands.")
        }
        let commandData = try command.encoded()
        let opcode = command.code
        let device = self.device
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PTPTransactionResult, Error>) in
            let once = ResumeOnce(continuation)
            let timer = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { once.resume(throwing: PTPError.timeout(operation: opcode)) }
            }
            device.requestSendPTPCommand(commandData, outData: outData) { inData, responseData, error in
                Task { @MainActor in
                    timer.cancel()
                    if let error {
                        once.resume(throwing: PTPError.transport(error.localizedDescription))
                        return
                    }
                    // Expected: second buffer = response container. If that fails but the first
                    // buffer is a well-formed response container, the order is the other way round
                    // on this OS build; accept it and record it (docs/ptp-validation.md, check P2).
                    if let response = try? PTPContainer.decode(responseData), response.type == .response {
                        once.resume(returning: PTPTransactionResult(response: response, inData: inData))
                    } else if let response = try? PTPContainer.decode(inData), response.type == .response {
                        Self.observedSwappedBuffers = true
                        once.resume(returning: PTPTransactionResult(response: response, inData: responseData))
                    } else {
                        once.resume(throwing: PTPError.transport("Unrecognised ImageCaptureCore PTP response (\(responseData.count) B / \(inData.count) B)."))
                    }
                }
            }
        }
    }

    func close() async {
        isClosed = true
    }
}

/// Guards a continuation against double resumption (completion vs. timeout race).
@MainActor
private final class ResumeOnce<T> {
    private var continuation: CheckedContinuation<T, Error>?
    init(_ c: CheckedContinuation<T, Error>) { continuation = c }
    func resume(returning value: sending T) { continuation?.resume(returning: value); continuation = nil }
    func resume(throwing error: Error) { continuation?.resume(throwing: error); continuation = nil }
}

/// Discovers USB cameras with `ICDeviceBrowser` and opens an ImageCaptureCore session.
///
/// This is the hardware spike for milestone 1–2 (discover, identify, harmless read). It does
/// not claim any USB interface directly; it only uses public ImageCaptureCore APIs.
@MainActor
final class ImageCaptureCameraBrowser: NSObject {
    enum Event {
        case authorization(AuthorizationState)
        case found(ICCameraDevice)
        case removed(ICDevice)
        case sessionError(String)
    }

    enum AuthorizationState: Equatable {
        case notDetermined, authorized, denied, restricted, notRequired
    }

    /// USB camera control is unavailable in the iOS Simulator: ImageCaptureCore there doesn't
    /// implement control authorization (calling it raises "unrecognized selector").
    nonisolated static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #elseif os(iOS)
        ICDeviceBrowser.instancesRespond(to: NSSelectorFromString("requestControlAuthorizationWithCompletion:"))
        #else
        true
        #endif
    }

    var onEvent: ((Event) -> Void)?
    private let browser = ICDeviceBrowser()
    private(set) var cameras: [ICCameraDevice] = []
    private(set) var isBrowsing = false

    override init() {
        super.init()
        browser.delegate = self
        let mask = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask) ?? .camera
    }

    var authorizationState: AuthorizationState {
        #if os(iOS)
        Self.map(browser.controlAuthorizationStatus)
        #else
        .notRequired
        #endif
    }

    /// Requests camera-control authorization (iOS 14+) and starts browsing.
    func start() async {
        #if os(iOS)
        var state = authorizationState
        if state == .notDetermined {
            state = await withCheckedContinuation { (cont: CheckedContinuation<AuthorizationState, Never>) in
                browser.requestControlAuthorization { status in
                    let mapped = Self.map(status)
                    cont.resume(returning: mapped)
                }
            }
        }
        onEvent?(.authorization(state))
        guard state == .authorized else { return }
        #else
        onEvent?(.authorization(.notRequired))
        #endif
        if !isBrowsing {
            browser.start()
            isBrowsing = true
        }
    }

    func stop() {
        if isBrowsing { browser.stop() }
        isBrowsing = false
    }

    #if os(iOS)
    nonisolated private static func map(_ status: ICAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }
    #endif

    func openSession(_ device: ICCameraDevice) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            device.requestOpenSession(options: nil) { error in
                if let error { cont.resume(throwing: PTPError.transport(error.localizedDescription)) } else { cont.resume() }
            }
        }
    }

    func closeSession(_ device: ICCameraDevice) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            device.requestCloseSession(options: nil) { _ in cont.resume() }
        }
    }
}

extension ImageCaptureCameraBrowser: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        // Delegate threading isn't documented; hop to the main actor instead of asserting it.
        nonisolated(unsafe) let unsafeCamera = camera
        Task { @MainActor in
            unsafeCamera.delegate = self
            self.cameras.append(unsafeCamera)
            self.onEvent?(.found(unsafeCamera))
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        nonisolated(unsafe) let unsafeDevice = device
        Task { @MainActor in
            self.cameras.removeAll { $0 === unsafeDevice }
            self.onEvent?(.removed(unsafeDevice))
        }
    }
}

extension ImageCaptureCameraBrowser: ICCameraDeviceDelegate {
    nonisolated func didRemove(_ device: ICDevice) {}
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in self.onEvent?(.sessionError(message)) }
        }
    }
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}
