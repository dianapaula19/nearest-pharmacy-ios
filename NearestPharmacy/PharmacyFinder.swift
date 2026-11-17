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

    static let listSize = 10

    private(set) var state: State = .locating
    private(set) var origin: CLLocation?
    var address = ""

    private let search: any PharmacySearching
    private let locationProvider: any LocationProviding
    @ObservationIgnored private var lastRequest: (() async throws -> CLLocation)?
    @ObservationIgnored private var requestID = UUID()

    init(
        search: any PharmacySearching = MapKitPharmacySearch(),
        location: any LocationProviding = DeviceLocationProvider()
    ) {
        self.search = search
        self.locationProvider = location
    }

    var nearest: Pharmacy? {
        guard case .loaded(let pharmacies) = state else { return nil }
        return pharmacies.first
    }

    /// The pharmacies after the nearest one, up to `listSize`.
    var others: [Pharmacy] {
        guard case .loaded(let pharmacies) = state else { return [] }
        return Array(pharmacies.dropFirst().prefix(Self.listSize))
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
        state = .searching
        do {
            let results = try await search.pharmacies(near: origin)
            // A newer search started while this one was in flight; let it win.
            guard id == requestID else { return }
            state = results.isEmpty ? .empty : .loaded(Self.sorted(results, from: origin))
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
