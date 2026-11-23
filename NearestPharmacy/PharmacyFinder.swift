import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class PharmacyFinder {
    enum State: Equatable {
        case locating
        case searching
        case loaded([Pharmacy])
        case empty
        /// Location is unavailable or the address wasn't found: the user should type (another) address.
        case needsAddress(String)
        /// Something went wrong that retrying may fix, e.g. no network.
        case failed(String)
    }

    /// The nearest pharmacy plus this many more are shown.
    static let listSize = 10

    private(set) var state: State = .locating
    private(set) var origin: CLLocation?
    private(set) var selectedIndex = 0
    var address = ""

    private let search: any PharmacySearching
    private let locationProvider: any LocationProviding
    private let directions: any WalkingDirections
    /// The directions request for the current selection; tests await it.
    @ObservationIgnored private(set) var directionsTask: Task<Void, Never>?
    @ObservationIgnored private var lastRequest: (() async throws -> CLLocation)?
    @ObservationIgnored private var requestID = UUID()

    init(
        search: any PharmacySearching,
        location: any LocationProviding,
        directions: any WalkingDirections
    ) {
        self.search = search
        self.locationProvider = location
        self.directions = directions
    }

    // Default dependencies are built here, not as default arguments: default-argument expressions
    // run in a nonisolated context, where these @MainActor initialisers can't be called.
    convenience init() {
        self.init(
            search: MapKitPharmacySearch(),
            location: DeviceLocationProvider(),
            directions: MapKitWalkingDirections()
        )
    }

    /// The nearest pharmacies, nearest first.
    var pharmacies: [Pharmacy] {
        guard case .loaded(let pharmacies) = state else { return [] }
        return Array(pharmacies.prefix(Self.listSize + 1))
    }

    var selected: Pharmacy? {
        pharmacies.indices.contains(selectedIndex) ? pharmacies[selectedIndex] : nil
    }

    /// Walking route to the selected pharmacy: Apple Maps walking directions once they arrive, a straight
    /// line until then or if they fail.
    private(set) var route: [GeoPoint] = []

    /// How far the walk is: along the route once there is one, otherwise as the crow flies.
    var walkMeters: CLLocationDistance {
        route.count > 2 ? route.length : selected?.distance ?? 0
    }

    /// Picks a pharmacy by position, wrapping around at either end like a menu in the game.
    func select(_ index: Int) {
        guard !pharmacies.isEmpty else { return }
        selectedIndex = (index % pharmacies.count + pharmacies.count) % pharmacies.count
        updateRoute()
        fetchDirections()
    }

    private func fetchDirections() {
        directionsTask?.cancel()
        guard let origin, let selected else { return }
        let (from, to, index) = (GeoPoint(origin.coordinate), GeoPoint(selected.coordinate), selectedIndex)
        directionsTask = Task {
            guard let path = try? await directions.route(from: from, to: to), !Task.isCancelled, index == selectedIndex else { return }
            route = path
        }
    }

    private func updateRoute() {
        guard let origin, let selected else {
            route = []
            return
        }
        route = [GeoPoint(origin.coordinate), GeoPoint(selected.coordinate)]
    }

    func useCurrentLocation() async {
        await find { [locationProvider] in try await locationProvider.currentLocation() }
    }

    func searchAddress() async {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        await find { [locationProvider] in try await locationProvider.location(for: query) }
    }

    func retry() async {
        guard let lastRequest else { return }
        await find(lastRequest)
    }

    private func find(_ resolveOrigin: @escaping () async throws -> CLLocation) async {
        let id = UUID()
        requestID = id
        lastRequest = resolveOrigin
        state = .locating

        let origin: CLLocation
        do {
            origin = try await resolveOrigin()
        } catch {
            guard id == requestID, !(error is CancellationError) else { return }
            if let error = error as? LocationError {
                state = .needsAddress(error.localizedDescription)
            } else {
                state = .failed(Self.message(for: error))
            }
            return
        }

        guard id == requestID else { return }
        self.origin = origin
        selectedIndex = 0
        route = []
        directionsTask?.cancel()
        state = .searching
        do {
            let results = try await search.pharmacies(near: origin)
            // A newer search started while this one was in flight; let it win.
            guard id == requestID else { return }
            state = results.isEmpty ? .empty : .loaded(Self.sorted(results, from: origin))
            updateRoute()
            fetchDirections()
        } catch {
            guard id == requestID else { return }
            state = .failed(Self.message(for: error))
        }
    }

    static func sorted(_ pharmacies: [Pharmacy], from origin: CLLocation) -> [Pharmacy] {
        pharmacies
            .map { pharmacy in
                var pharmacy = pharmacy
                pharmacy.distance = pharmacy.location.distance(from: origin)
                return pharmacy
            }
            .sorted { $0.distance < $1.distance }
    }

    static func message(for error: Error) -> String {
        if (error as? MKError)?.code == .loadingThrottled {
            return String(localized: "Too many searches in a short time. Wait a moment and try again.")
        }
        if (error as? URLError)?.code == .notConnectedToInternet || (error as? CLError)?.code == .network {
            return String(localized: "You're offline. Check your connection and try again.")
        }
        return String(localized: "Couldn't load pharmacies. Check your connection and try again.")
    }
}
