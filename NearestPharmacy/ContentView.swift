import MapKit
import SwiftUI

struct ContentView: View {
    @State private var finder = PharmacyFinder()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("Blush"))
                .navigationTitle("Dr. Mochi's Pharmacies")
                .searchable(text: $finder.address, placement: .navigationBarDrawer(displayMode: .always), prompt: "Address or city ♡")
                .onSubmit(of: .search) {
                    Task { await finder.searchAddress() }
                }
                .toolbar {
                    Button("Use My Location", systemImage: "location.fill") {
                        Task { await finder.useCurrentLocation() }
                    }
                }
        }
        .fontDesign(.rounded)
        .task { await finder.useCurrentLocation() }
    }

    @ViewBuilder
    private var content: some View {
        switch finder.state {
        case .locating:
            MochiSays("Sniffing out where you are… 🐾", bouncing: true)
        case .searching:
            MochiSays("Checking every pharmacy nearby… ✿", bouncing: true)
        case .needsAddress(let message):
            MochiSays("\(message) I'll find the closest one from there! 💕")
        case .empty:
            MochiSays("Oh no, no pharmacies within 30 km. Try another address? 🥺")
        case .failed(let message):
            MochiSays("\(message) 😿") {
                Button("Try Again ♡") {
                    Task { await finder.retry() }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        case .loaded:
            if let nearest = finder.nearest, let origin = finder.origin {
                ResultsView(origin: origin, nearest: nearest, others: finder.others)
            }
        }
    }
}

/// Dr. Mochi with a speech bubble, used for every non-result state.
private struct MochiSays<Actions: View>: View {
    let message: String
    var bouncing = false
    @ViewBuilder var actions: Actions
    @State private var up = false

    init(_ message: String, bouncing: Bool = false, @ViewBuilder actions: () -> Actions) {
        self.message = message
        self.bouncing = bouncing
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .multilineTextAlignment(.center)
                .padding(18)
                .background(.background, in: .rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.tint.opacity(0.35), lineWidth: 2))
            Image("Mochi")
                .resizable()
                .scaledToFit()
                .frame(width: 130)
                .offset(y: up ? -8 : 0)
                .animation(bouncing ? .easeInOut(duration: 0.5).repeatForever() : .default, value: up)
                .onAppear { up = bouncing }
                .accessibilityLabel("Dr. Mochi, the cat pharmacist")
            actions
        }
        .padding(32)
    }
}

private extension MochiSays where Actions == EmptyView {
    init(_ message: String, bouncing: Bool = false) {
        self.init(message, bouncing: bouncing) { EmptyView() }
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
            if let tip = QuickerAlternative(nearest: nearest, others: others) {
                Section {
                    TipView(tip: tip)
                }
                .listRowBackground(Color.mint.opacity(0.15))
            }
            Section {
                PharmacyMap(origin: origin, pharmacies: [nearest] + others)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
            if !others.isEmpty {
                Section("Also Nearby ✿") {
                    ForEach(others) { pharmacy in
                        PharmacyRow(pharmacy: pharmacy)
                    }
                }
            }
            Section {
            } footer: {
                Text("Steps and calories are estimates for an average adult. Crowd levels are simulated for fun ♡")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct NearestPharmacyCard: View {
    let pharmacy: Pharmacy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("♡ Nearest pharmacy")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(pharmacy.name)
                .font(.title2.bold())
            Text("\(pharmacy.distance.formattedDistance) away")
                .font(.headline)
                .foregroundStyle(.tint)
            WalkStats(distance: pharmacy.distance)
            CrowdBadge(crowd: Crowd(key: pharmacy.crowdKey))
            if let address = pharmacy.address {
                Text(address)
                    .foregroundStyle(.secondary)
            }
            Button("Directions ✿", systemImage: "pawprint.fill", action: pharmacy.openDirections)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}

private struct WalkStats: View {
    let distance: CLLocationDistance

    var body: some View {
        HStack(spacing: 6) {
            Chip("🐾 \(Estimates.steps(distance).formatted()) steps")
            Chip("🔥 \(Estimates.calories(distance)) kcal")
            Chip("⏱️ \(Estimates.walkMinutes(distance)) min")
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Chip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.14), in: .capsule)
    }
}

private struct CrowdBadge: View {
    let crowd: Crowd

    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var text: String {
        let label = crowd.level.label
        guard crowd.people > 0 else { return "\(label) · no queue" }
        return "\(label) · ~\(crowd.people) \(crowd.people == 1 ? "person" : "people"), ~\(crowd.waitMinutes) min wait"
    }

    private var color: Color {
        switch crowd.level {
        case .quiet: .mint
        case .moderate: .orange
        case .busy: .pink
        }
    }
}

private extension Crowd.Level {
    var label: String {
        switch self {
        case .quiet: "🌸 Quiet"
        case .moderate: "🍓 A bit busy"
        case .busy: "🐝 Busy"
        }
    }
}

private struct TipView: View {
    let tip: QuickerAlternative

    var body: some View {
        Button(action: tip.pharmacy.openDirections) {
            HStack(spacing: 12) {
                Image("Mochi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54)
                    .accessibilityHidden(true)
                Text("**Psst!** \(tip.pharmacy.name) is \(tip.extraMeters.formattedDistance) farther, but it's usually quieter right now. You'd probably be served about \(tip.minutesSaved) min sooner 💨")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityHint("Opens directions in Maps")
    }
}

private struct PharmacyRow: View {
    let pharmacy: Pharmacy

    var body: some View {
        Button(action: pharmacy.openDirections) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pharmacy.name)
                        .foregroundStyle(.primary)
                    if let address = pharmacy.address {
                        Text(address)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("🐾 \(Estimates.steps(pharmacy.distance).formatted()) · 🔥 \(Estimates.calories(pharmacy.distance)) kcal · \(Crowd(key: pharmacy.crowdKey).level.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(pharmacy.distance.formattedDistance)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.tint)
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
            ForEach(Array(pharmacies.enumerated()), id: \.element.id) { index, pharmacy in
                Marker(pharmacy.name, systemImage: index == 0 ? "heart.fill" : "cross.fill", coordinate: pharmacy.coordinate)
                    .tint(index == 0 ? Color.accentColor : .pink.opacity(0.6))
            }
            Marker("Search location", systemImage: "person.fill", coordinate: origin.coordinate)
                .tint(.purple)
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
