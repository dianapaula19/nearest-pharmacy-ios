# Nearest Pharmacy (iOS)

A SwiftUI app that finds the pharmacy nearest to you. It shows the pharmacy's distance and address with a **Directions** button that opens Apple Maps, plus a map and the next ten nearest.

Its web counterpart is [nearest-pharmacy-web](https://github.com/dianapaula19/nearest-pharmacy-web).

## Run it

Requires Xcode 16 or later (iOS 17+ deployment target). No API keys, packages or signing setup.

1. `open NearestPharmacy.xcodeproj`
2. Pick an iPhone simulator and press **⌘R**.
3. Allow location access when asked. The Simulator reports a simulated location; to see Helsinki, run this while the Simulator is booted:

   ```sh
   xcrun simctl location booted set 60.1699,24.9384
   ```

   or use **Features › Location › Custom Location…** in the Simulator.

Run the tests with **⌘U**, or from the terminal:

```sh
xcodebuild test -project NearestPharmacy.xcodeproj -scheme NearestPharmacy \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

(Use any simulator listed by `xcrun simctl list devices available`.)

## How it works

| File | What's in it |
| --- | --- |
| `PharmacyFinder.swift` | `@Observable` view model: one `State` enum for locating → searching → loaded / empty / needs address / failed, sorting, error messages, retry |
| `PharmacySearch.swift` | `PharmacySearching` protocol and the MapKit implementation: `MKLocalPointsOfInterestRequest` with `MKPointOfInterestFilter(including: [.pharmacy])`, widening 3 → 10 → 30 km only when nothing is found |
| `LocationProvider.swift` | `LocationProviding` protocol and the Core Location implementation: async wrapper around `CLLocationManager` for permission and a one-shot fix, and `CLGeocoder` for typed addresses |
| `Pharmacy.swift` | Model wrapping the `MKMapItem`, so **Directions** opens Apple Maps' own place card via `openInMaps` |
| `ContentView.swift` | Search bar, states (`ContentUnavailableView` with **Try Again**), nearest-pharmacy card, `Map` with markers, list |

Distances come from `CLLocation.distance(from:)` and are formatted with `Measurement`, which follows the user's locale (km or miles).

If location access is denied or restricted, the app explains why and asks for an address instead. The search bar is always available to look somewhere else.

### Tests

`NearestPharmacyTests` uses Swift Testing with mock `PharmacySearching` and `LocationProviding` implementations. It covers sorting, the ten-item limit, the empty state, the denied, restricted and unavailable location states, typed and unknown addresses, a network failure followed by a successful retry, and the separate throttling message.

## Data source and its limits

- **Apple Maps POI search** is free, keyless and native. It returns at most about 25 results per request, which is plenty for the nearest and next ten.
- **Opening hours** aren't exposed by MapKit's public API, so the app doesn't show them. **Directions** opens the full Apple Maps place card, which includes them.
- Searches are rate-limited per device. If that happens the app shows a "wait a moment" message with a retry.

## Trade-offs

- **Swift 5 language mode** keeps the project building across Xcode versions. Everything that touches UI, MapKit or Core Location is `@MainActor`, which keeps a later move to Swift 6 strict concurrency small.
- **Two small protocols instead of a DI framework.** Production defaults are passed in the view model's initialiser, and tests inject mocks.
- **No coordinator or extra layers.** One screen, one view model.

## What I'd do next

- Highlight a pharmacy on the map when its row is selected, and the reverse.
- Use `CLLocationUpdate` / `CLServiceSession` on iOS 18+ to follow the user as they walk.
- Add a UI test for the denied-permission path with a launch argument that injects a mock provider.
- Add localisation for Finnish and Swedish; the strings already go through `String(localized:)`.
