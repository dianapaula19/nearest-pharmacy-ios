import MapKit

struct Pharmacy: Identifiable, Equatable {
    let id = UUID()
    let mapItem: MKMapItem
    /// Metres from the search origin. Set by `PharmacyFinder` when sorting.
    var distance: CLLocationDistance = 0

    var name: String { mapItem.name ?? String(localized: "Pharmacy") }
    var coordinate: CLLocationCoordinate2D { mapItem.placemark.coordinate }
    var address: String? { mapItem.placemark.title }
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
    /// Same pharmacy → same key across searches, unlike `id`.
    var crowdKey: String { "\(name)@\(coordinate.latitude),\(coordinate.longitude)" }

    /// Opens Apple Maps with walking directions to this pharmacy.
    func openDirections() {
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
