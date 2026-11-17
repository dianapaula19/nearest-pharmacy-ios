import MapKit
import SwiftUI

struct ContentView: View {
    @State private var finder = PharmacyFinder()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PolkaDots())
                .navigationTitle("Hello Kitty's Pharmacies 🎀")
                .searchable(text: $finder.address, placement: .navigationBarDrawer(displayMode: .always), prompt: "Address or city 🎀")
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
            KittySays("Looking for where you are… 🎀", bouncing: true)
        case .searching:
            KittySays("Checking every pharmacy nearby… ✿", bouncing: true)
        case .needsAddress(let message):
            KittySays("\(message) I'll find the closest one from there! 💕")
        case .empty:
            KittySays("Oh no, no pharmacies within 30 km. Try another address? 🥺")
        case .failed(let message):
            KittySays("\(message) 😿") {
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

/// Hello Kitty with a speech bubble, used for every non-result state.
private struct KittySays<Actions: View>: View {
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
            KittyPharmacist(width: 130)
                .offset(y: up ? -8 : 0)
                .animation(bouncing ? .easeInOut(duration: 0.5).repeatForever() : .default, value: up)
                .onAppear { up = bouncing }
            actions
        }
        .padding(32)
    }
}

private extension KittySays where Actions == EmptyView {
    init(_ message: String, bouncing: Bool = false) {
        self.init(message, bouncing: bouncing) { EmptyView() }
    }
}

/// Hello Kitty wearing a pharmacist's cap with a red cross.
private struct KittyPharmacist: View {
    let width: CGFloat

    var body: some View {
        Image("HelloKitty")
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.6), radius: 0.8)
            .overlay(alignment: .topLeading) {
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: width * 0.2, topTrailingRadius: width * 0.2)
                        .fill(.white)
                        .stroke(.black.opacity(0.75), lineWidth: max(1, width / 60))
                    Image(systemName: "cross.fill")
                        .font(.system(size: width * 0.09))
                        .foregroundStyle(.red)
                }
                .frame(width: width * 0.42, height: width * 0.2)
                .rotationEffect(.degrees(-14))
                .offset(x: width * 0.1, y: -width * 0.04)
            }
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

/// Sanrio-style pink polka dots.
private struct PolkaDots: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 40
            for row in 0...Int(size.height / step) {
                for column in 0...Int(size.width / step) {
                    let x = CGFloat(column) * step + (row.isMultiple(of: 2) ? 0 : step / 2)
                    let dot = CGRect(x: x, y: CGFloat(row) * step, width: 10, height: 10)
                    context.fill(Path(ellipseIn: dot), with: .color(.pink.opacity(0.18)))
                }
            }
        }
        .background(Color("Blush"))
        .ignoresSafeArea()
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
                Section("Also Nearby 🎀") {
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
            Text("🎀 Nearest pharmacy")
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
            Button("Directions 🎀", systemImage: "heart.fill", action: pharmacy.openDirections)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            KittyPharmacist(width: 64)
                .padding(.top, 12)
        }
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
                KittyPharmacist(width: 54)
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
