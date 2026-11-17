import CoreGraphics
import Foundation
import Testing
@testable import NearestPharmacy

// A small grid of streets:  1 — 2 — 3
//                           |         |
//                           4 ——————— 5      plus a detached street 6 — 7
private let at: [Int: GeoPoint] = [
    1: GeoPoint(lat: 60.17, lon: 24.93), 2: GeoPoint(lat: 60.17, lon: 24.94), 3: GeoPoint(lat: 60.17, lon: 24.95),
    4: GeoPoint(lat: 60.16, lon: 24.93), 5: GeoPoint(lat: 60.16, lon: 24.95),
    6: GeoPoint(lat: 60.20, lon: 25.00), 7: GeoPoint(lat: 60.20, lon: 25.01),
]
private func road(_ nodes: Int...) -> Town.Road { Town.Road(kind: .minor, nodes: nodes, points: nodes.map { at[$0]! }) }
private let router = StreetRouter(roads: [road(1, 2, 3), road(1, 4), road(4, 5), road(5, 3), road(6, 7)])

struct StreetRouterTests {
    @Test func followsTheStreetsTheShortWayRound() throws {
        let from = GeoPoint(lat: 60.1701, lon: 24.9301), to = GeoPoint(lat: 60.1701, lon: 24.9501)
        let path = try #require(router.path(from: from, to: to))
        #expect(path.first == from)
        #expect(path.last == to)
        #expect(Array(path.dropFirst().dropLast()) == [at[1]!, at[2]!, at[3]!])
    }

    @Test func ignoresADetachedStreetEvenWhenItIsClosest() throws {
        let island = GeoPoint(lat: 60.1702, lon: 24.9302)
        let withIsland = StreetRouter(roads: [road(1, 2, 3), road(1, 4), road(4, 5), road(5, 3),
                                              Town.Road(kind: .minor, nodes: [8, 9], points: [island, GeoPoint(lat: 60.1703, lon: 24.9303)])])
        let path = try #require(withIsland.path(from: island, to: at[3]!))
        #expect(Array(path.dropFirst().dropLast()) == [at[1]!, at[2]!, at[3]!])
    }

    @Test func givesUpFarFromAnyStreet() {
        #expect(router.path(from: at[1]!, to: GeoPoint(lat: 61, lon: 25)) == nil)
    }

    @Test func addsUpTheLegs() {
        #expect(abs(StreetRouter.length(of: [at[1]!, at[2]!, at[3]!]) - 2 * at[1]!.distance(to: at[2]!)) < 1)
    }
}

struct TownLayoutTests {
    private let street = (a: CGPoint(x: 0, y: 200), b: CGPoint(x: 800, y: 200))

    @Test func keepsBuildingsOffTheStreetsAndEachOther() {
        let center = TownLayout.rect(at: CGPoint(x: 400, y: 150), size: TownLayout.centerSize)
        let (buildings, _) = TownLayout.place(
            segments: [street],
            sites: [(id: 1, at: CGPoint(x: 100, y: 150)), (id: 2, at: CGPoint(x: 300, y: 230)), (id: 3, at: CGPoint(x: 400, y: 140))],
            reserved: [center],
            seed: 1
        )
        let rects = buildings.map { TownLayout.rect(at: $0.at, size: TownLayout.kinds[$0.kind].size) }
        #expect(buildings.contains { $0.at == CGPoint(x: 100, y: 150) })
        #expect(!buildings.contains { $0.at == CGPoint(x: 400, y: 140) })
        for (i, r) in rects.enumerated() {
            #expect(!r.intersects(center))
            #expect(TownLayout.distance(from: CGPoint(x: r.midX, y: r.midY), to: street) >= min(r.width, r.height) * 0.45)
            for other in rects[(i + 1)...] { #expect(!r.intersects(other)) }
        }
    }

    @Test func plantsTreesNearTheStreetsOnly() {
        let (_, trees) = TownLayout.place(segments: [street], sites: [], reserved: [], seed: 1)
        #expect(!trees.isEmpty)
        for t in trees { #expect((26...140).contains(TownLayout.distance(from: t, to: street))) }
    }

    @Test func aBuildingAlwaysLooksTheSame() {
        #expect(TownLayout.kind(for: 42) == TownLayout.kind(for: 42))
        #expect(TownLayout.kinds.indices.contains(TownLayout.kind(for: 123_456)))
    }
}

@MainActor
struct OverpassTownLoaderTests {
    @Test func parsesStreetsAndBuildingCentres() throws {
        let json = """
        {"elements": [
          {"type": "way", "id": 100, "tags": {"highway": "primary"}, "nodes": [1, 2],
           "geometry": [{"lat": 60.169, "lon": 24.938}, {"lat": 60.17, "lon": 24.939}]},
          {"type": "way", "id": 101, "tags": {"highway": "residential"}, "nodes": [2, 3],
           "geometry": [{"lat": 60.17, "lon": 24.939}, {"lat": 60.17, "lon": 24.941}]},
          {"type": "way", "id": 200, "center": {"lat": 60.1698, "lon": 24.9381}}
        ]}
        """
        let town = try OverpassTownLoader.parse(Data(json.utf8))
        #expect(town.roads.map(\.kind) == [.major, .minor])
        #expect(town.roads[0].nodes == [1, 2])
        #expect(town.buildings.map(\.id) == [200])
    }

    @Test func asksForStreetsAndBuildingsAroundThePoint() {
        let query = OverpassTownLoader.query(around: GeoPoint(lat: 60.1699, lon: 24.9384))
        #expect(query.contains("residential"))
        #expect(query.contains("way[\"building\"](around:900,60.1699,24.9384);out ids center qt;"))
    }
}

struct WaterMaskTests {
    @Test func tellsWaterFromLand() {
        #expect(WaterMask.isWater(r: 158, g: 200, b: 245)) // Apple Maps water
        #expect(!WaterMask.isWater(r: 247, g: 245, b: 240)) // land
        #expect(!WaterMask.isWater(r: 210, g: 234, b: 200)) // park
        #expect(!WaterMask.isWater(r: 255, g: 255, b: 255)) // road
    }
}
