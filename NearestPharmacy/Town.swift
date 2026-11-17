import CoreLocation
import Foundation

/// A latitude/longitude pair that, unlike `CLLocationCoordinate2D`, is `Hashable`.
struct GeoPoint: Hashable, Sendable {
    let lat: Double
    let lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(lat: coordinate.latitude, lon: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    func distance(to other: GeoPoint) -> CLLocationDistance {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: other.lat, longitude: other.lon))
    }
}

/// The streets and buildings around the user, from OpenStreetMap, used to draw the town.
struct Town: Sendable {
    struct Road: Sendable {
        enum Kind: Sendable { case major, minor }
        let kind: Kind
        /// OSM node ids; streets share them at junctions, which is what connects them for routing.
        let nodes: [Int]
        let points: [GeoPoint]
    }

    struct Building: Sendable {
        let id: Int
        let center: GeoPoint
    }

    var roads: [Road]
    var buildings: [Building]
}

@MainActor
protocol TownLoading {
    func town(around center: GeoPoint) async throws -> Town
}

/// Loads streets and building centres from the public Overpass API. No key needed.
struct OverpassTownLoader: TownLoading {
    static let radius = 900
    // Tried in order: the main instance is often at capacity, so fall back to a mirror.
    static let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://maps.mail.ru/osm/tools/overpass/api/interpreter")!,
    ]
    // The instances answer 429/504 when busy and ask clients to back off.
    static let retryDelays: [Duration] = [.seconds(1), .seconds(2)]

    // Streets only: separately mapped sidewalks would make the download several MB.
    // Buildings come back as bare centres, which keeps thousands of them small.
    static func query(around c: GeoPoint) -> String {
        let around = "(around:\(radius),\(c.lat),\(c.lon))"
        let streets = "\"highway\"~\"^(primary|secondary|tertiary|unclassified|residential|living_street|pedestrian)$\""
        return "[out:json][timeout:25];way[\(streets)]\(around);out geom qt;way[\"building\"]\(around);out ids center qt;"
    }

    func town(around center: GeoPoint) async throws -> Town {
        var request = URLRequest(url: Self.endpoints[0])
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = "data=" + Self.query(around: center).addingPercentEncoding(withAllowedCharacters: allowed)!
        request.httpBody = Data(body.utf8)

        var lastError: Error = URLError(.badServerResponse)
        for attempt in 0...Self.retryDelays.count {
            if attempt > 0 { try await Task.sleep(for: Self.retryDelays[attempt - 1]) }
            for endpoint in Self.endpoints {
                request.url = endpoint
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if (response as? HTTPURLResponse)?.statusCode == 200 {
                        return try Self.parse(data)
                    }
                } catch {
                    if error is CancellationError { throw error }
                    lastError = error
                }
            }
        }
        throw lastError
    }

    private struct Response: Decodable {
        struct Point: Decodable {
            let lat: Double
            let lon: Double
        }

        struct Element: Decodable {
            let type: String
            let id: Int
            let tags: [String: String]?
            let nodes: [Int]?
            let geometry: [Point]?
            let center: Point?
        }

        let elements: [Element]
    }

    private static let majorRoads: Set = ["motorway", "trunk", "primary", "secondary", "tertiary"]

    static func parse(_ data: Data) throws -> Town {
        let elements = try JSONDecoder().decode(Response.self, from: data).elements.filter { $0.type == "way" }
        let roads = elements.compactMap { el -> Town.Road? in
            guard let highway = el.tags?["highway"], let nodes = el.nodes, let geometry = el.geometry,
                  geometry.count > 1, geometry.count == nodes.count else { return nil }
            return Town.Road(
                kind: majorRoads.contains(highway) ? .major : .minor,
                nodes: nodes,
                points: geometry.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
            )
        }
        let buildings = elements.compactMap { el -> Town.Building? in
            guard el.tags == nil, let c = el.center else { return nil }
            return Town.Building(id: el.id, center: GeoPoint(lat: c.lat, lon: c.lon))
        }
        return Town(roads: roads, buildings: buildings)
    }
}
