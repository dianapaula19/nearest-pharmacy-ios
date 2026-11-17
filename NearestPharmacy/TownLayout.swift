import CoreGraphics
import CoreLocation

/// Projects coordinates onto a flat "world" in game pixels around a centre point.
/// One pixel is about 1.2 m, close to the web app's zoom 16, so sprites keep their size.
struct WorldProjection {
    static let metersPerPixel = 1.2
    let center: GeoPoint

    func point(_ p: GeoPoint) -> CGPoint {
        let metersPerDegreeLat = 111_132.0
        let metersPerDegreeLon = 111_320.0 * cos(center.lat * .pi / 180)
        return CGPoint(
            x: (p.lon - center.lon) * metersPerDegreeLon / Self.metersPerPixel,
            y: -(p.lat - center.lat) * metersPerDegreeLat / Self.metersPerPixel
        )
    }
}

/// Lays out the town: a game building on real building spots and along the streets, trees near the
/// streets. A port of the web app's `world.ts`.
enum TownLayout {
    /// A sprite size, anchored at its bottom centre; `weight` is how common it is.
    struct Kind {
        let asset: String
        let size: CGSize
        let weight: Double
    }

    struct Placed {
        let kind: Int
        let at: CGPoint
    }

    static let kinds = [
        Kind(asset: "House", size: CGSize(width: 80, height: 57), weight: 5),
        Kind(asset: "Annex", size: CGSize(width: 80, height: 66), weight: 2),
        Kind(asset: "Mart", size: CGSize(width: 64, height: 64), weight: 1.2),
        Kind(asset: "Gym", size: CGSize(width: 112, height: 81), weight: 0.8),
        Kind(asset: "Museum", size: CGSize(width: 176, height: 114), weight: 0.4),
    ]
    static let treeSize = CGSize(width: 30, height: 41)
    static let centerSize = CGSize(width: 80, height: 72)

    private static let gap: CGFloat = 4
    private static let streetSpacing: CGFloat = 90
    private static let streetOffset: CGFloat = 14
    private static let treeGrid: CGFloat = 44
    private static let treeChance = 0.5
    // Trees grow near streets only, which keeps them out of lakes and the sea.
    private static let treeRoadDistance: ClosedRange<CGFloat> = 26...140

    typealias Segment = (a: CGPoint, b: CGPoint)

    static func distance(from p: CGPoint, to s: Segment) -> CGFloat {
        let dx = s.b.x - s.a.x, dy = s.b.y - s.a.y
        let lengthSq = dx * dx + dy * dy
        let t = lengthSq == 0 ? 0 : max(0, min(1, ((p.x - s.a.x) * dx + (p.y - s.a.y) * dy) / lengthSq))
        return hypot(p.x - (s.a.x + t * dx), p.y - (s.a.y + t * dy))
    }

    static func rect(at p: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: p.x - size.width / 2, y: p.y - size.height, width: size.width, height: size.height)
    }

    /// Weighted pick that depends only on `id`, so a building always looks the same.
    static func kind(for id: Int) -> Int {
        var roll = Double(UInt32(truncatingIfNeeded: id &* 2_654_435_761)) / 4_294_967_296
        let total = kinds.reduce(0) { $0 + $1.weight }
        for (i, kind) in kinds.enumerated() {
            roll -= kind.weight / total
            if roll < 0 { return i }
        }
        return kinds.count - 1
    }

    static func place(
        segments: [Segment],
        sites: [(id: Int, at: CGPoint)],
        reserved: [CGRect],
        seed: UInt64
    ) -> (buildings: [Placed], trees: [CGPoint]) {
        // Spatial buckets keep every check local; a city centre has thousands of streets and buildings.
        var streets = Buckets<Segment>()
        for s in segments {
            streets.insert(s, covering: CGRect(x: min(s.a.x, s.b.x), y: min(s.a.y, s.b.y), width: abs(s.b.x - s.a.x), height: abs(s.b.y - s.a.y)))
        }
        var taken = Buckets<CGRect>()
        for r in reserved { taken.insert(r, covering: r) }
        var buildings: [Placed] = []

        // Only distances up to `treeRoadDistance.upperBound` matter; anything farther counts as far away.
        let nearestRoad = { (p: CGPoint) -> CGFloat in
            let reach = treeRoadDistance.upperBound
            let near = streets.items(in: CGRect(x: p.x - reach, y: p.y - reach, width: reach * 2, height: reach * 2))
            return near.map { distance(from: p, to: $0) }.min() ?? .infinity
        }
        let isFree = { (r: CGRect) in
            !taken.items(in: r.insetBy(dx: -gap, dy: -gap)).contains { $0.insetBy(dx: -gap, dy: -gap).intersects(r) }
        }

        func tryPlace(_ kind: Int, at p: CGPoint) {
            let size = kinds[kind].size
            let r = rect(at: p, size: size)
            // The sprite's middle must stay off the pavement, or buildings would sit on the streets.
            guard isFree(r), nearestRoad(CGPoint(x: r.midX, y: r.midY)) >= min(size.width, size.height) * 0.45 else { return }
            taken.insert(r, covering: r)
            buildings.append(Placed(kind: kind, at: p))
        }

        for site in sites { tryPlace(kind(for: site.id), at: site.at) }

        // Big city blocks have a single centre, so fill the gaps by lining the streets with more buildings.
        for s in segments {
            let length = hypot(s.b.x - s.a.x, s.b.y - s.a.y)
            guard length > 0 else { continue }
            let ux = (s.b.x - s.a.x) / length, uy = (s.b.y - s.a.y) / length
            var side: CGFloat = 1
            for d in stride(from: streetSpacing / 2, to: length, by: streetSpacing) {
                let k = kind(for: Int(s.a.x * 31 + s.a.y * 17 + d))
                let size = kinds[k].size
                let offset = size.height / 2 + streetOffset
                tryPlace(k, at: CGPoint(x: s.a.x + ux * d - uy * offset * side, y: s.a.y + uy * d + ux * offset * side + size.height / 2))
                side = -side
            }
        }

        var random = SplitMix64(seed: seed)
        var trees: [CGPoint] = []
        let bounds = segments.reduce(CGRect.null) { $0.union(CGRect(x: $1.a.x, y: $1.a.y, width: 0, height: 0)).union(CGRect(x: $1.b.x, y: $1.b.y, width: 0, height: 0)) }
        guard !bounds.isNull else { return (buildings, trees) }
        for y in stride(from: bounds.minY, through: bounds.maxY, by: treeGrid) {
            for x in stride(from: bounds.minX, through: bounds.maxX, by: treeGrid) {
                let p = CGPoint(x: x + (random.unit() - 0.5) * 24, y: y + (random.unit() - 0.5) * 24)
                guard random.unit() < treeChance, treeRoadDistance.contains(nearestRoad(p)) else { continue }
                let r = rect(at: p, size: treeSize)
                if isFree(r) {
                    taken.insert(r, covering: r)
                    trees.append(p)
                }
            }
        }
        return (buildings, trees)
    }
}

/// Small deterministic PRNG, so the same town always grows the same trees.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

/// Items bucketed by the grid cells their bounding box covers.
private struct Buckets<Item> {
    private static var cell: CGFloat { 160 }
    private var cells: [Int64: [Item]] = [:]

    private static func keys(covering r: CGRect) -> [Int64] {
        let x0 = Int64((r.minX / cell).rounded(.down)), x1 = Int64((r.maxX / cell).rounded(.down))
        let y0 = Int64((r.minY / cell).rounded(.down)), y1 = Int64((r.maxY / cell).rounded(.down))
        return (x0...x1).flatMap { x in (y0...y1).map { y in x &* 1_000_003 &+ y } }
    }

    mutating func insert(_ item: Item, covering r: CGRect) {
        for key in Self.keys(covering: r) { cells[key, default: []].append(item) }
    }

    /// Items whose cells overlap `r` (may include a few that don't overlap `r` itself).
    func items(in r: CGRect) -> [Item] {
        Self.keys(covering: r).flatMap { cells[$0] ?? [] }
    }
}
