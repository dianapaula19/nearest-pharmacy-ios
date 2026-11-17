import CoreLocation
import MapKit
import Testing
@testable import NearestPharmacy

@MainActor
final class MockSearch: PharmacySearching {
    var result: Result<[Pharmacy], Error>
    private(set) var searchedLocations: [CLLocation] = []

    init(_ result: Result<[Pharmacy], Error>) {
        self.result = result
    }

    func pharmacies(near location: CLLocation) async throws -> [Pharmacy] {
        searchedLocations.append(location)
        return try result.get()
    }
}

@MainActor
final class MockLocation: LocationProviding {
    var current: Result<CLLocation, Error>
    var geocoded: [String: CLLocation] = [:]

    init(_ current: Result<CLLocation, Error>) {
        self.current = current
    }

    func currentLocation() async throws -> CLLocation {
        try current.get()
    }

    func location(for address: String) async throws -> CLLocation {
        guard let location = geocoded[address] else { throw LocationError.addressNotFound(address) }
        return location
    }
}

private let helsinki = CLLocation(latitude: 60.1699, longitude: 24.9384)

private func pharmacy(_ name: String, _ latitude: Double, _ longitude: Double) -> Pharmacy {
    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    item.name = name
    return Pharmacy(mapItem: item)
}

@MainActor
struct PharmacyFinderTests {
    @Test func sortsPharmaciesNearestFirst() async {
        let search = MockSearch(.success([
            pharmacy("Far", 60.2000, 24.9400),
            pharmacy("Near", 60.1700, 24.9390),
            pharmacy("Mid", 60.1800, 24.9400),
        ]))
        let finder = PharmacyFinder(search: search, location: MockLocation(.success(helsinki)))

        await finder.useCurrentLocation()

        #expect(finder.nearest?.name == "Near")
        #expect(finder.others.map(\.name) == ["Mid", "Far"])
        #expect(finder.others.allSatisfy { $0.distance > finder.nearest!.distance })
        #expect(finder.origin == helsinki)
    }

    @Test func limitsTheListToTenAfterTheNearest() async {
        let many = (0..<25).map { pharmacy("P\($0)", 60.17 + Double($0) * 0.001, 24.94) }
        let finder = PharmacyFinder(search: MockSearch(.success(many)), location: MockLocation(.success(helsinki)))

        await finder.useCurrentLocation()

        #expect(finder.others.count == PharmacyFinder.listSize)
    }

    @Test func showsEmptyStateWhenNothingIsFound() async {
        let finder = PharmacyFinder(search: MockSearch(.success([])), location: MockLocation(.success(helsinki)))

        await finder.useCurrentLocation()

        #expect(finder.state == .empty)
        #expect(finder.nearest == nil)
    }

    @Test(arguments: [LocationError.denied, .restricted, .unavailable])
    func asksForAnAddressWhenLocationIsUnavailable(error: LocationError) async {
        let search = MockSearch(.success([pharmacy("Near", 60.17, 24.939)]))
        let finder = PharmacyFinder(search: search, location: MockLocation(.failure(error)))

        await finder.useCurrentLocation()

        #expect(finder.state == .needsAddress(error.localizedDescription))
        #expect(search.searchedLocations.isEmpty)
    }

    @Test func searchesAroundATypedAddress() async {
        let tampere = CLLocation(latitude: 61.4978, longitude: 23.7610)
        let location = MockLocation(.failure(LocationError.denied))
        location.geocoded["Tampere"] = tampere
        let search = MockSearch(.success([pharmacy("Tampereen apteekki", 61.498, 23.761)]))
        let finder = PharmacyFinder(search: search, location: location)

        finder.address = "  Tampere "
        await finder.searchAddress()

        #expect(search.searchedLocations == [tampere])
        #expect(finder.nearest?.name == "Tampereen apteekki")
    }

    @Test func reportsAnUnknownAddress() async {
        let finder = PharmacyFinder(search: MockSearch(.success([])), location: MockLocation(.success(helsinki)))

        finder.address = "Nowhere at all"
        await finder.searchAddress()

        #expect(finder.state == .needsAddress(LocationError.addressNotFound("Nowhere at all").localizedDescription))
    }

    @Test func ignoresABlankAddress() async {
        let search = MockSearch(.success([]))
        let finder = PharmacyFinder(search: search, location: MockLocation(.success(helsinki)))

        finder.address = "   "
        await finder.searchAddress()

        #expect(search.searchedLocations.isEmpty)
        #expect(finder.state == .locating)
    }

    @Test func showsAnErrorAndRecoversOnRetry() async {
        let search = MockSearch(.failure(URLError(.notConnectedToInternet)))
        let finder = PharmacyFinder(search: search, location: MockLocation(.success(helsinki)))

        await finder.useCurrentLocation()
        #expect(finder.state == .failed(PharmacyFinder.message(for: URLError(.notConnectedToInternet))))

        search.result = .success([pharmacy("Near", 60.17, 24.939)])
        await finder.retry()

        #expect(finder.nearest?.name == "Near")
        #expect(search.searchedLocations.count == 2)
    }

    @Test func explainsThrottlingSeparately() {
        let throttled = PharmacyFinder.message(for: MKError(.loadingThrottled))
        let offline = PharmacyFinder.message(for: URLError(.notConnectedToInternet))
        let other = PharmacyFinder.message(for: MKError(.serverFailure))

        #expect(Set([throttled, offline, other]).count == 3)
    }
}
