import MapKit
import SwiftUI

struct ContentView: View {
    @State private var finder = PharmacyFinder()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Nearest Pharmacy")
                .searchable(text: $finder.address, placement: .navigationBarDrawer(displayMode: .always), prompt: "Address or city")
                .onSubmit(of: .search) {
                    Task { await finder.searchAddress() }
                }
                .toolbar {
                    Button("Use My Location", systemImage: "location.fill") {
                        Task { await finder.useCurrentLocation() }
                    }
                }
        }
        .task { await finder.useCurrentLocation() }
    }

    @ViewBuilder
    private var content: some View {
        switch finder.state {
        case .locating:
            ProgressView("Finding your location…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .searching:
            ProgressView("Looking for pharmacies…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsAddress(let message):
            ContentUnavailableView("Search for an Address", systemImage: "location.slash", description: Text(message))
        case .empty:
            ContentUnavailableView(
                "No Pharmacies Found",
                systemImage: "cross.case",
                description: Text("There are no pharmacies within 30 km. Try another address.")
            )
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Pharmacies", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await finder.retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if let nearest = finder.nearest, let origin = finder.origin {
                ResultsView(origin: origin, nearest: nearest, others: finder.others)
            }
        }
    }
}

private struct ResultsView: View {
    let origin: CLLocation
    let nearest: Pharmacy
    let others: [Pharmacy]

    var body: some View {
        List {
            Section {
                NearestPharmacyCard(pharmacy: nearest)
            }
            Section {
                PharmacyMap(origin: origin, pharmacies: [nearest] + others)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
            if !others.isEmpty {
                Section("Also Nearby") {
                    ForEach(others) { pharmacy in
                        PharmacyRow(pharmacy: pharmacy)
                    }
                }
            }
        }
    }
}

private struct NearestPharmacyCard: View {
    let pharmacy: Pharmacy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nearest pharmacy")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(pharmacy.name)
                .font(.title2.bold())
            Text("\(pharmacy.distance.formattedDistance) away")
                .font(.headline)
                .foregroundStyle(.tint)
            if let address = pharmacy.address {
                Text(address)
                    .foregroundStyle(.secondary)
            }
            Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill", action: pharmacy.openDirections)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}

private struct PharmacyRow: View {
    let pharmacy: Pharmacy

    var body: some View {
        Button(action: pharmacy.openDirections) {
            HStack {
                VStack(alignment: .leading) {
                    Text(pharmacy.name)
                        .foregroundStyle(.primary)
                    if let address = pharmacy.address {
                        Text(address)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(pharmacy.distance.formattedDistance)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHint("Opens directions in Maps")
    }
}

private struct PharmacyMap: View {
    let origin: CLLocation
    let pharmacies: [Pharmacy]

    var body: some View {
        Map(initialPosition: .automatic) {
            Marker("Search location", systemImage: "person.fill", coordinate: origin.coordinate)
                .tint(.blue)
            ForEach(Array(pharmacies.enumerated()), id: \.element.id) { index, pharmacy in
                Marker(pharmacy.name, systemImage: "cross.fill", coordinate: pharmacy.coordinate)
                    .tint(index == 0 ? Color.accentColor : .gray)
            }
        }
        // Re-frame the camera whenever a new search finishes.
        .id(pharmacies.first?.id)
        .accessibilityLabel("Map of nearby pharmacies")
    }
}

private extension CLLocationDistance {
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
