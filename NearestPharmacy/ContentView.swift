import MapKit
import SwiftUI

struct ContentView: View {
    @State private var finder = PharmacyFinder()
    @AppStorage("player") private var player: Player = .leaf

    var body: some View {
        NavigationStack {
            ScrollView {
                content.padding(16)
            }
            .background { PewterCity() }
            .navigationTitle("Pharmacy Finder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $finder.address, placement: .navigationBarDrawer(displayMode: .always), prompt: "Address or city")
            .onSubmit(of: .search) {
                Task { await finder.searchAddress() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Walk as", selection: $player) {
                            ForEach(Player.allCases) { Text($0.name).tag($0) }
                        }
                    } label: {
                        Sprite(name: player.asset, size: CGSize(width: 14, height: 19), scale: 1.5)
                    }
                    .accessibilityLabel("Walk as \(player.name)")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use My Location", systemImage: "location.fill") {
                        Task { await finder.useCurrentLocation() }
                    }
                }
            }
        }
        .font(Theme.font(17))
        .tint(Theme.dialogue)
        .task { await finder.useCurrentLocation() }
    }

    @ViewBuilder
    private var content: some View {
        switch finder.state {
        case .locating:
            JoySays("Hello, and welcome! Let me look up where you are…")
        case .searching:
            JoySays("I'm checking every pharmacy nearby. This only takes a moment…")
        case .needsAddress(let message):
            JoySays("\(message) I'll find the closest one from there!")
        case .empty:
            JoySays("I'm sorry, there are no pharmacies within 30 km. Try another address?")
        case .failed(let message):
            JoySays(message) {
                Button("Try Again") {
                    Task { await finder.retry() }
                }
                .buttonStyle(DialogueButtonStyle())
            }
        case .loaded:
            if let origin = finder.origin, let selected = finder.selected {
                ResultsView(finder: finder, origin: origin, selected: selected, player: player)
            }
        }
    }
}

/// Pewter City from FireRed behind everything, faded so the panels stay readable.
private struct PewterCity: View {
    var body: some View {
        Image("PewterCity")
            .interpolation(.none)
            .resizable()
            .scaledToFill()
            .overlay(Color.white.opacity(0.25))
            .ignoresSafeArea()
    }
}

private struct ResultsView: View {
    let finder: PharmacyFinder
    let origin: CLLocation
    let selected: Pharmacy
    let player: Player

    private var pharmacies: [Pharmacy] { finder.pharmacies }

    /// Length of the walk along the route, or the straight-line distance until there is one.
    private var walkMeters: CLLocationDistance {
        finder.route.count > 2 ? StreetRouter.length(of: finder.route) : selected.distance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            card
            if finder.selectedIndex == 0, let tip = QuickerAlternative(nearest: pharmacies[0], others: Array(pharmacies.dropFirst())) {
                TipView(tip: tip) { finder.select(pharmacies.firstIndex(of: tip.pharmacy) ?? 0) }
            }
            MapSection(finder: finder, origin: origin, player: player)
            list
            Text("Steps and calories are estimates for an average adult. Crowd levels are simulated for fun.")
                .font(Theme.font(13))
                .multilineTextAlignment(.center)
                .panel(padding: 10)
        }
        // Arrow keys on a hardware keyboard move through the pharmacies like a menu in the game.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { finder.select(finder.selectedIndex + 1); return .handled }
        .onKeyPress(.rightArrow) { finder.select(finder.selectedIndex + 1); return .handled }
        .onKeyPress(.upArrow) { finder.select(finder.selectedIndex - 1); return .handled }
        .onKeyPress(.leftArrow) { finder.select(finder.selectedIndex - 1); return .handled }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(finder.selectedIndex == 0 ? "NEAREST TO YOU" : "NO. \(finder.selectedIndex + 1) OF \(pharmacies.count)")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Previous pharmacy", systemImage: "arrowtriangle.left.fill") { finder.select(finder.selectedIndex - 1) }
                Button("Next pharmacy", systemImage: "arrowtriangle.right.fill") { finder.select(finder.selectedIndex + 1) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(DialogueButtonStyle())

            Text(selected.name)
                .font(Theme.font(26, relativeTo: .title).weight(.bold))
                .textCase(.uppercase)
            Text("\(selected.distance.formattedDistance) away" + (finder.route.count > 2 ? " · \(walkMeters.formattedDistance) on foot" : ""))
                .font(Theme.font(19, relativeTo: .headline).weight(.bold))
            HStack(spacing: 16) {
                Text("\(Estimates.steps(walkMeters).formatted()) STEPS")
                Text("\(Estimates.calories(walkMeters)) KCAL")
                Text("\(Estimates.walkMinutes(walkMeters)) MIN WALK")
            }
            .font(Theme.font(16).weight(.bold))
            QueueBar(crowd: Crowd(key: selected.crowdKey))
            if let address = selected.address {
                Text(address)
            }
            Button("Directions", action: selected.openDirections)
                .buttonStyle(DialogueButtonStyle())
                .padding(.top, 6)
        }
        .panel(padding: 20)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHARMACIES NEARBY")
                .font(Theme.font(17).weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Theme.panel, in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.panelBorder, lineWidth: 3))
            VStack(spacing: 0) {
                ForEach(Array(pharmacies.enumerated()), id: \.element.id) { index, pharmacy in
                    PharmacyRow(pharmacy: pharmacy, isSelected: index == finder.selectedIndex) { finder.select(index) }
                    if index < pharmacies.count - 1 { Divider().overlay(Theme.panelBorder.opacity(0.3)) }
                }
            }
            .panel(padding: 6)
        }
    }
}

private struct MapSection: View {
    let finder: PharmacyFinder
    let origin: CLLocation
    let player: Player
    @State private var showTown = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if showTown, let town = finder.town {
                    TownView(
                        town: town,
                        origin: GeoPoint(origin.coordinate),
                        pharmacies: finder.pharmacies,
                        selectedIndex: finder.selectedIndex,
                        route: finder.route,
                        player: player,
                        onSelect: finder.select
                    )
                } else {
                    RegularMap(finder: finder, origin: origin)
                }
            }
            .frame(height: 340)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.panelBorder, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelShadow).offset(x: 8, y: 8))

            if finder.town != nil {
                HStack(spacing: 6) {
                    Button("Town") { showTown = true }.opacity(showTown ? 1 : 0.6)
                    Button("Map") { showTown = false }.opacity(showTown ? 0.6 : 1)
                }
                .buttonStyle(DialogueButtonStyle())
                .padding(12)
            } else {
                Text("Building the town…")
                    .font(Theme.font(14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .dialogue(padding: 0)
                    .fixedSize()
                    .padding(12)
            }
        }
    }
}

/// The regular Apple map with plain pins: no town, no route, no animation.
private struct RegularMap: View {
    let finder: PharmacyFinder
    let origin: CLLocation

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(Array(finder.pharmacies.enumerated()), id: \.element.id) { index, pharmacy in
                Marker(pharmacy.name, coordinate: pharmacy.coordinate)
                    .tint(index == finder.selectedIndex ? Theme.red : .gray)
            }
            Marker("You", systemImage: "person.fill", coordinate: origin.coordinate)
                .tint(.blue)
        }
        .accessibilityLabel("Map of nearby pharmacies")
    }
}

private struct TipView: View {
    let tip: QuickerAlternative
    let select: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Sprite.nurseJoy(scale: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text("**Psst!** \(tip.pharmacy.name) is \(tip.extraMeters.formattedDistance) farther, but it's usually quieter right now. You'd probably be served about \(tip.minutesSaved) min sooner.")
                    .font(Theme.font(16))
                Button("Show me", action: select)
                    .font(Theme.font(16).weight(.bold))
                    .foregroundStyle(Theme.link)
            }
        }
        .dialogue(padding: 16)
    }
}

private struct PharmacyRow: View {
    let pharmacy: Pharmacy
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                // The menu cursor from the game marks the chosen pharmacy.
                Triangle()
                    .rotation(.degrees(-90))
                    .fill(Theme.panelText)
                    .frame(width: 10, height: 12)
                    .opacity(isSelected ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pharmacy.name).font(Theme.font(17).weight(.bold))
                    if let address = pharmacy.address {
                        Text(address).font(Theme.font(14)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Text("\(Estimates.steps(pharmacy.distance).formatted()) steps · \(Estimates.calories(pharmacy.distance)) kcal · \(Crowd(key: pharmacy.crowdKey).level.label)")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(pharmacy.distance.formattedDistance).font(Theme.font(16).weight(.bold))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isSelected ? Theme.hpGreen.opacity(0.25) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows the way there")
    }
}

extension CLLocationDistance {
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
