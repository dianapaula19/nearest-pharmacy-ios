import CoreLocation

enum LocationError: LocalizedError, Equatable, Sendable {
    case denied
    case restricted
    case unavailable
    case addressNotFound(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            String(localized: "Location access is off. Search for an address or city instead, or allow location in Settings.")
        case .restricted:
            String(localized: "Location access is restricted on this device. Search for an address or city instead.")
        case .unavailable:
            String(localized: "Your location couldn't be determined. Search for an address or city instead.")
        case .addressNotFound(let query):
            String(localized: "Couldn't find “\(query)”. Try a street address or city name.")
        }
    }
}

@MainActor
protocol LocationProviding {
    func currentLocation() async throws -> CLLocation
    func location(for address: String) async throws -> CLLocation
}

/// Wraps `CLLocationManager`'s delegate callbacks in async calls.
@MainActor
final class DeviceLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .denied: throw LocationError.denied
        case .restricted: throw LocationError.restricted
        default: break
        }
        // A newer request replaces an older one still waiting for a fix.
        locationContinuation?.resume(throwing: CancellationError())
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func location(for address: String) async throws -> CLLocation {
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.geocodeAddressString(address)
        } catch let error as CLError where error.code == .geocodeFoundNoResult {
            throw LocationError.addressNotFound(address)
        }
        guard let location = placemarks.first?.location else { throw LocationError.addressNotFound(address) }
        return location
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let denied = (error as? CLError)?.code == .denied
            locationContinuation?.resume(throwing: denied ? LocationError.denied : LocationError.unavailable)
            locationContinuation = nil
        }
    }
}
