import Foundation
import Observation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// The phone's location for camera geotags, like XApp's SMARTPHONE LOCATION SYNC. Off until
/// the user turns it on; then sent to the paired camera only when the camera asks.
@Observable
@MainActor
final class PhoneLocation: NSObject {
    enum Status: Equatable, Sendable { case off, needsPermission, denied, active }

    private(set) var status: Status = .off
    private(set) var latest: (latitude: Double, longitude: Double, altitude: Double)?
    private(set) var latestDate: Date?
    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    #endif

    var isSharing: Bool { status == .active }

    func setSharing(_ on: Bool) {
        #if canImport(CoreLocation)
        guard on else {
            manager.stopUpdatingLocation()
            status = .off
            latest = nil
            return
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        apply(manager.authorizationStatus)
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        #endif
    }

    #if canImport(CoreLocation)
    private func apply(_ auth: CLAuthorizationStatus) {
        switch auth {
        case .notDetermined: status = .needsPermission
        case .denied, .restricted: status = .denied
        default:
            status = .active
            manager.startUpdatingLocation()
        }
    }
    #endif
}

#if canImport(CoreLocation)
extension PhoneLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        MainActor.assumeIsolated { if status != .off { apply(auth) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let fix = (l.coordinate.latitude, l.coordinate.longitude, l.altitude)
        let at = l.timestamp
        MainActor.assumeIsolated {
            guard status == .active else { return }
            latest = (latitude: fix.0, longitude: fix.1, altitude: fix.2)
            latestDate = at
        }
    }
}
#endif
