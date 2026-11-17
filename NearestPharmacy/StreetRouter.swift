import CoreLocation

/// Shortest walks along the streets of a `Town`, so the dotted route always follows the pavement.
struct StreetRouter {
    private struct Edge {
        let to: Int
        let meters: CLLocationDistance
    }

    private var points: [Int: GeoPoint] = [:]
    private var edges: [Int: [Edge]] = [:]

    init(roads: [Town.Road]) {
        var points: [Int: GeoPoint] = [:]
        var edges: [Int: [Edge]] = [:]
        for road in roads {
            for (id, point) in zip(road.nodes, road.points) { points[id] = point }
            for i in road.nodes.indices.dropFirst() {
                let meters = road.points[i - 1].distance(to: road.points[i])
                edges[road.nodes[i - 1], default: []].append(Edge(to: road.nodes[i], meters: meters))
                edges[road.nodes[i], default: []].append(Edge(to: road.nodes[i - 1], meters: meters))
            }
        }
        // Keep only the biggest connected set of streets. Small islands (a square's outline, a cut-off
        // alley) would otherwise be picked as the nearest street and leave no way out.
        var seen = Set<Int>()
        var largest: [Int] = []
        for start in points.keys where !seen.contains(start) {
            var component = [start]
            seen.insert(start)
            var i = 0
            while i < component.count {
                for edge in edges[component[i]] ?? [] {
                    if seen.insert(edge.to).inserted { component.append(edge.to) }
                }
                i += 1
            }
            if component.count > largest.count { largest = component }
        }
        let keep = Set(largest)
        self.points = points.filter { keep.contains($0.key) }
        self.edges = edges.filter { keep.contains($0.key) }
    }

    private func nearestNode(to p: GeoPoint, within maxMeters: CLLocationDistance) -> Int? {
        var best: Int?
        var bestMeters = maxMeters
        for (id, point) in points {
            let meters = point.distance(to: p)
            if meters < bestMeters {
                best = id
                bestMeters = meters
            }
        }
        return best
    }

    /// The walk from `from` to `to` along the streets, starting and ending at the given points.
    /// Nil if either end is more than `snapMeters` from a street.
    func path(from: GeoPoint, to: GeoPoint, snapMeters: CLLocationDistance = 250) -> [GeoPoint]? {
        guard let start = nearestNode(to: from, within: snapMeters),
              let goal = nearestNode(to: to, within: snapMeters) else { return nil }

        var distance = [start: 0.0]
        var previous: [Int: Int] = [:]
        var queue = MinHeap()
        queue.push((0, start))
        while let next = queue.pop() {
            let (meters, node) = next
            if node == goal { break }
            if meters > distance[node, default: .infinity] { continue }
            for edge in edges[node] ?? [] {
                let next = meters + edge.meters
                if next < distance[edge.to, default: .infinity] {
                    distance[edge.to] = next
                    previous[edge.to] = node
                    queue.push((next, edge.to))
                }
            }
        }
        guard distance[goal] != nil else { return nil }

        var route: [GeoPoint] = []
        var node: Int? = goal
        while let current = node {
            route.append(points[current]!)
            node = previous[current]
        }
        return [from] + route.reversed() + [to]
    }

    static func length(of path: [GeoPoint]) -> CLLocationDistance {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
}

/// Minimal binary heap keyed by distance, for Dijkstra.
private struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ item: (Double, Int)) {
        items.append(item)
        var i = items.count - 1
        while i > 0, items[(i - 1) / 2].0 > items[i].0 {
            items.swapAt(i, (i - 1) / 2)
            i = (i - 1) / 2
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var smallest = i
            if l < items.count, items[l].0 < items[smallest].0 { smallest = l }
            if r < items.count, items[r].0 < items[smallest].0 { smallest = r }
            if smallest == i { break }
            items.swapAt(i, smallest)
            i = smallest
        }
        return top
    }
}
