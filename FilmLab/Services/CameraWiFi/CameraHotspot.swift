import Foundation
#if os(iOS) && canImport(NetworkExtension)
import NetworkExtension
#endif

/// Joins the camera's own Wi‑Fi network from inside the app (one system prompt, no trip to
/// Settings), the step FUJIFILM XApp sends you to Settings for on many bodies.
///
/// Needs the Hotspot Configuration capability on the App ID (`com.apple.developer.networking.
/// HotspotConfiguration`). Without it — or on the Simulator — `join` throws `.unavailable` and the
/// UI tells the user to join the network in Settings instead.
enum CameraHotspot {
    enum JoinError: Error, LocalizedError, Equatable {
        case unavailable
        case userDenied
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: "Join the camera's Wi‑Fi in Settings › Wi‑Fi, then come back."
            case .userDenied: "You declined joining the camera's Wi‑Fi."
            case .failed(let m): "Couldn't join the camera's Wi‑Fi: \(m)"
            }
        }
    }

    /// `passphrase` nil = open network. Networks started over Bluetooth are hidden WPA2
    /// (petabyt/fudge `WiFi.java`), hence `hidden`.
    static func join(ssid: String, passphrase: String?, hidden: Bool = false) async throws {
        #if os(iOS) && canImport(NetworkExtension) && !targetEnvironment(simulator)
        let config = passphrase.map { NEHotspotConfiguration(ssid: ssid, passphrase: $0, isWEP: false) }
            ?? NEHotspotConfiguration(ssid: ssid)
        // Session-only: iOS drops the camera network when FilmLab is done with it, so the phone
        // goes straight back to the user's normal Wi‑Fi.
        config.joinOnce = true
        config.hidden = hidden
        do {
            try await NEHotspotConfigurationManager.shared.apply(config)
        } catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain {
            switch NEHotspotConfigurationError(rawValue: error.code) {
            case .alreadyAssociated: return
            case .userDenied: throw JoinError.userDenied
            case .internal, .systemConfiguration, .unknown: throw JoinError.unavailable
            default: throw JoinError.failed(error.localizedDescription)
            }
        } catch {
            throw JoinError.unavailable
        }
        #else
        throw JoinError.unavailable
        #endif
    }

    /// Joins the first open network whose name starts with "FUJIFILM-" (the camera's own network
    /// when WIRELESS COMMUNICATION is open; prefix per community reports, NV).
    static func joinAnyFujifilm() async throws {
        #if os(iOS) && canImport(NetworkExtension) && !targetEnvironment(simulator)
        let config = NEHotspotConfiguration(ssidPrefix: "FUJIFILM-")
        config.joinOnce = true
        do { try await NEHotspotConfigurationManager.shared.apply(config) }
        catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain {
            switch NEHotspotConfigurationError(rawValue: error.code) {
            case .alreadyAssociated: return
            case .userDenied: throw JoinError.userDenied
            default: throw JoinError.unavailable
            }
        } catch { throw JoinError.unavailable }
        #else
        throw JoinError.unavailable
        #endif
    }

    static func leave(ssid: String) {
        #if os(iOS) && canImport(NetworkExtension) && !targetEnvironment(simulator)
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
        #endif
    }
}
