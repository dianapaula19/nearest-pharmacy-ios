import MapKit

@MainActor
protocol WalkingDirections {
    func route(from: GeoPoint, to: GeoPoint) async throws -> [GeoPoint]
}

/// Apple Maps walking directions: real streets, footpaths and bridges. No key needed.
struct MapKitWalkingDirections: WalkingDirections {
    func route(from: GeoPoint, to: GeoPoint) async throws -> [GeoPoint] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        request.transportType = .walking
        let response = try await MKDirections(request: request).calculate()
        guard let polyline = response.routes.first?.polyline else { throw MKError(.directionsNotFound) }
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        // Directions start and end on the nearest path; join up with the exact points.
        return [from] + coordinates.map(GeoPoint.init) + [to]
    }
}
