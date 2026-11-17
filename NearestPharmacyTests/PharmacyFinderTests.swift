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

@MainActor
final class MockTown: TownLoading {
    var result: Result<Town, Error>

    init(_ result: Result<Town, Error> = .failure(URLError(.notConnectedToInternet))) {
        self.result = result
    }

    func town(around center: GeoPoint) async throws -> Town {
        try result.get()
    }
}

@MainActor
final class MockDirections: WalkingDirections {
    var result: Result<[GeoPoint], Error>

    init(_ result: Result<[GeoPoint], Error> = .failure(MKError(.directionsNotFound))) {
        self.result = result
    }

    func route(from: GeoPoint, to: GeoPoint) async throws -> [GeoPoint] {
        try result.get()
    }
}

private let helsinki = CLLocation(latitude: 60.1699, longitude: 24.9384)

private func pharmacy(_ name: String, _ latitude: Double, _ longitude: Double) -> Pharmacy {
    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    item.name = name
    return Pharmacy(mapItem: item)
}

@MainActor
private func makeFinder(
    _ search: MockSearch,
    location: MockLocation = MockLocation(.success(helsinki)),
    town: MockTown = MockTown(),
    directions: MockDirections = MockDirections()
) -> PharmacyFinder {
    PharmacyFinder(search: search, location: location, town: town, directions: directions)
}

@MainActor
struct PharmacyFinderTests {
    @Test func sortsPharmaciesNearestFirst() async {
        let finder = makeFinder(MockSearch(.success([
            pharmacy("Far", 60.2000, 24.9400),
            pharmacy("Near", 60.1700, 24.9390),
            pharmacy("Mid", 60.1800, 24.9400),
        ])))

        await finder.useCurrentLocation()

        #expect(finder.pharmacies.map(\.name) == ["Near", "Mid", "Far"])
        #expect(finder.selected?.name == "Near")
        #expect(finder.pharmacies[0].distance < finder.pharmacies[1].distance)
        #expect(finder.origin == helsinki)
    }

    @Test func showsTheNearestPlusTen() async {
        let many = (0..<25).map { pharmacy("P\($0)", 60.17 + Double($0) * 0.001, 24.94) }
        let finder = makeFinder(MockSearch(.success(many)))

        await finder.useCurrentLocation()

        #expect(finder.pharmacies.count == PharmacyFinder.listSize + 1)
    }

    @Test func selectionWrapsAroundLikeAGameMenu() async {
        let finder = makeFinder(MockSearch(.success([pharmacy("A", 60.170, 24.939), pharmacy("B", 60.171, 24.939), pharmacy("C", 60.172, 24.939)])))
        await finder.useCurrentLocation()

        finder.select(1)
        #expect(finder.selected?.name == "B")
        finder.select(3)
        #expect(finder.selected?.name == "A")
        finder.select(-1)
        #expect(finder.selected?.name == "C")
    }

    @Test func routesStraightWhenThereIsNoTownOrDirections() async {
        let finder = makeFinder(MockSearch(.success([pharmacy("Near", 60.1700, 24.9390)])))

        await finder.useCurrentLocation()
        await finder.directionsTask?.value

        #expect(finder.town == nil)
        #expect(finder.route == [GeoPoint(helsinki.coordinate), GeoPoint(lat: 60.1700, lon: 24.9390)])
    }

    @Test func routesAlongTheTownsStreets() async {
        let corner = GeoPoint(lat: 60.1699, lon: 24.9390)
        let streets = Town(
            roads: [Town.Road(kind: .minor, nodes: [1, 2, 3], points: [GeoPoint(helsinki.coordinate), corner, GeoPoint(lat: 60.1700, lon: 24.9390)])],
            buildings: []
        )
        let finder = makeFinder(MockSearch(.success([pharmacy("Near", 60.1700, 24.9390)])), town: MockTown(.success(streets)))

        await finder.useCurrentLocation()
        await finder.directionsTask?.value

        #expect(finder.town != nil)
        #expect(finder.route.contains(corner))
    }

    @Test func prefersRealWalkingDirections() async {
        let bridge = GeoPoint(lat: 60.1650, lon: 24.9500)
        let finder = makeFinder(
            MockSearch(.success([pharmacy("Across the water", 60.1640, 24.9520)])),
            directions: MockDirections(.success([GeoPoint(helsinki.coordinate), bridge, GeoPoint(lat: 60.1640, lon: 24.9520)]))
        )

        await finder.useCurrentLocation()
        await finder.directionsTask?.value

        #expect(finder.route.contains(bridge))
    }

    @Test func showsEmptyStateWhenNothingIsFound() async {
        let finder = makeFinder(MockSearch(.success([])))

        await finder.useCurrentLocation()

        #expect(finder.state == .empty)
        #expect(finder.selected == nil)
    }

    @Test(arguments: [LocationError.denied, .restricted, .unavailable])
    func asksForAnAddressWhenLocationIsUnavailable(error: LocationError) async {
        let search = MockSearch(.success([pharmacy("Near", 60.17, 24.939)]))
        let finder = makeFinder(search, location: MockLocation(.failure(error)))

        await finder.useCurrentLocation()

        #expect(finder.state == .needsAddress(error.localizedDescription))
        #expect(search.searchedLocations.isEmpty)
    }

    @Test func searchesAroundATypedAddress() async {
        let tampere = CLLocation(latitude: 61.4978, longitude: 23.7610)
        let location = MockLocation(.failure(LocationError.denied))
        location.geocoded["Tampere"] = tampere
        let search = MockSearch(.success([pharmacy("Tampereen apteekki", 61.498, 23.761)]))
        let finder = makeFinder(search, location: location)

        finder.address = "  Tampere "
        await finder.searchAddress()

        #expect(search.searchedLocations == [tampere])
        #expect(finder.selected?.name == "Tampereen apteekki")
    }

    @Test func reportsAnUnknownAddress() async {
        let finder = makeFinder(MockSearch(.success([])))

        finder.address = "Nowhere at all"
        await finder.searchAddress()

        #expect(finder.state == .needsAddress(LocationError.addressNotFound("Nowhere at all").localizedDescription))
    }

    @Test func ignoresABlankAddress() async {
        let search = MockSearch(.success([]))
        let finder = makeFinder(search)

        finder.address = "   "
        await finder.searchAddress()

        #expect(search.searchedLocations.isEmpty)
        #expect(finder.state == .locating)
    }

    @Test func showsAnErrorAndRecoversOnRetry() async {
        let search = MockSearch(.failure(URLError(.notConnectedToInternet)))
        let finder = makeFinder(search)

        await finder.useCurrentLocation()
        #expect(finder.state == .failed(PharmacyFinder.message(for: URLError(.notConnectedToInternet))))

        search.result = .success([pharmacy("Near", 60.17, 24.939)])
        await finder.retry()

        #expect(finder.selected?.name == "Near")
        #expect(search.searchedLocations.count == 2)
    }

    @Test func explainsThrottlingSeparately() {
        let throttled = PharmacyFinder.message(for: MKError(.loadingThrottled))
        let offline = PharmacyFinder.message(for: URLError(.notConnectedToInternet))
        let other = PharmacyFinder.message(for: MKError(.serverFailure))

        #expect(Set([throttled, offline, other]).count == 3)
    }
}
