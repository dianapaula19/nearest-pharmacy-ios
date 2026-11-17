import MapKit

@MainActor
protocol PharmacySearching {
    func pharmacies(near location: CLLocation) async throws -> [Pharmacy]
}

/// Finds pharmacies with MapKit's points-of-interest search. No API key needed.
struct MapKitPharmacySearch: PharmacySearching {
    /// A pharmacy found within radius r is the true nearest, so widen only when nothing is found.
    static let radii: [CLLocationDistance] = [3_000, 10_000, 30_000]

    func pharmacies(near location: CLLocation) async throws -> [Pharmacy] {
        for radius in Self.radii {
            let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.pharmacy])
            do {
                let response = try await MKLocalSearch(request: request).start()
                if !response.mapItems.isEmpty {
                    return response.mapItems.map { Pharmacy(mapItem: $0) }
                }
            } catch let error as MKError where error.code == .placemarkNotFound {
                continue
            }
        }
        return []
    }
}
