import CoreLocation

/// A latitude/longitude pair that, unlike `CLLocationCoordinate2D`, is `Hashable`.
struct GeoPoint: Hashable, Sendable {
    let lat: Double
    let lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    func distance(to other: GeoPoint) -> CLLocationDistance {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: other.lat, longitude: other.lon))
    }
}

extension [GeoPoint] {
    /// Length of the walk along these points.
    var length: CLLocationDistance {
        zip(self, dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}
