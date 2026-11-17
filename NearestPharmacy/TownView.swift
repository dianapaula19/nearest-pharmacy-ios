import SwiftUI

/// Who walks the route. FireRed's two player characters.
enum Player: String, CaseIterable, Identifiable {
    case leaf, red
    var id: Self { self }
    var asset: String { rawValue.capitalized }
    var name: String { rawValue.capitalized }
}

/// Everything in the town, laid out once in world pixels (see `WorldProjection`).
struct TownScene {
    struct Street {
        let major: Bool
        let points: [CGPoint]
    }

    let projection: WorldProjection
    let streets: [Street]
    let buildings: [TownLayout.Placed]
    let trees: [CGPoint]
    let centers: [CGPoint]
    let origin: CGPoint
    let bounds: CGRect

    init(town: Town, origin: GeoPoint, pharmacies: [GeoPoint]) {
        let projection = WorldProjection(center: origin)
        self.projection = projection
        streets = town.roads.map { Street(major: $0.kind == .major, points: $0.points.map(projection.point)) }
        centers = pharmacies.map(projection.point)
        self.origin = projection.point(origin)
        let segments = streets.flatMap { s in zip(s.points, s.points.dropFirst()).map { (a: $0.0, b: $0.1) } }
        let layout = TownLayout.place(
            segments: segments,
            sites: town.buildings.map { (id: $0.id, at: projection.point($0.center)) },
            reserved: (centers + [self.origin]).map { TownLayout.rect(at: $0, size: TownLayout.centerSize) },
            seed: 1
        )
        buildings = layout.buildings
        trees = layout.trees
        bounds = streets.flatMap(\.points).reduce(CGRect(origin: self.origin, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }
}

struct TownView: View {
    let town: Town
    let origin: GeoPoint
    let pharmacies: [Pharmacy]
    let selectedIndex: Int
    /// Walking route to the selected pharmacy, from `origin`.
    let route: [GeoPoint]
    let player: Player
    let onSelect: (Int) -> Void

    @State private var scene: TownScene?
    @State private var water: WaterMask.Layer?
    @State private var pan: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Camera {
        let center: CGPoint
        let zoom: CGFloat

        func world(_ screen: CGPoint, in size: CGSize) -> CGPoint {
            CGPoint(x: (screen.x - size.width / 2) / zoom + center.x, y: (screen.y - size.height / 2) / zoom + center.y)
        }

        func apply(to context: inout GraphicsContext, size: CGSize) {
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: zoom, y: zoom)
            context.translateBy(x: -center.x, y: -center.y)
        }

        func visible(in size: CGSize) -> CGRect {
            let topLeft = world(.zero, in: size)
            return CGRect(origin: topLeft, size: CGSize(width: size.width / zoom, height: size.height / zoom))
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let scene {
                    let camera = camera(for: scene, size: geo.size)
                    Canvas { context, size in drawTown(scene, camera: camera, in: &context, size: size) }
                    TimelineView(.animation(paused: reduceMotion)) { timeline in
                        Canvas { context, size in
                            drawRoute(scene, camera: camera, time: timeline.date.timeIntervalSinceReferenceDate, in: &context, size: size)
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    Color(red: 115 / 255, green: 206 / 255, blue: 165 / 255)
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragging) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(4, max(0.3, zoom * value.magnification)) }
            )
            .onTapGesture { location in
                guard let scene else { return }
                let point = camera(for: scene, size: geo.size).world(location, in: geo.size)
                if let i = scene.centers.firstIndex(where: { TownLayout.rect(at: $0, size: TownLayout.centerSize).contains(point) }) {
                    onSelect(i)
                }
            }
        }
        .clipped()
        .task(id: "\(origin.lat),\(origin.lon),\(town.roads.count),\(town.buildings.count)") {
            let (town, origin, centers) = (town, origin, pharmacies.map { GeoPoint($0.coordinate) })
            // Laying out a city centre takes a moment, so keep it off the main thread.
            let built = await Task.detached(priority: .userInitiated) { TownScene(town: town, origin: origin, pharmacies: centers) }.value
            scene = built
            water = try? await WaterMask.make(around: built.projection, covering: built.bounds.insetBy(dx: -200, dy: -200))
        }
        .onChange(of: selectedIndex) {
            pan = .zero
            zoom = 1
        }
        .accessibilityElement()
        .accessibilityLabel("Town map with the walking route to \(pharmacies[selectedIndex].name)")
        .accessibilityHint("Drag to look around, pinch to zoom, tap a Pokémon Center to choose it.")
    }

    /// Frames the user and the selected pharmacy, then applies the user's pan and zoom.
    private func camera(for scene: TownScene, size: CGSize) -> Camera {
        let target = scene.centers[selectedIndex]
        let mid = CGPoint(x: (scene.origin.x + target.x) / 2, y: (scene.origin.y + target.y) / 2)
        let span = max(abs(target.x - scene.origin.x), abs(target.y - scene.origin.y)) + 240
        let fit = min(2, max(0.35, min(size.width, size.height) / span))
        let z = fit * zoom * pinch
        return Camera(
            center: CGPoint(x: mid.x - (pan.width + dragging.width) / z, y: mid.y - (pan.height + dragging.height) / z),
            zoom: z
        )
    }

    private func drawTown(_ scene: TownScene, camera: Camera, in context: inout GraphicsContext, size: CGSize) {
        camera.apply(to: &context, size: size)
        let visible = camera.visible(in: size).insetBy(dx: -200, dy: -200)

        context.fill(Path(camera.visible(in: size)), with: .tiledImage(Image("Grass"), scale: 2))
        if let water {
            context.draw(Image(decorative: water.image, scale: 1).interpolation(.none), in: water.rect)
        }

        // All kerbs first, then all paving on top, so junctions merge into one surface. The route is
        // paved too, so footpaths and bridges on it show up as walkable ground.
        let routeStreet = TownScene.Street(major: false, points: route.map(scene.projection.point))
        let shown = scene.streets.filter { $0.points.contains(where: visible.contains) } + [routeStreet]
        let layers: [(shading: GraphicsContext.Shading, extra: CGFloat)] = [
            (.color(Color(red: 0.6, green: 0.63, blue: 0.66)), 4),
            (.tiledImage(Image("Pavement")), 0),
        ]
        for (shading, extra) in layers {
            for street in shown {
                var path = Path()
                path.addLines(street.points)
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: (street.major ? 18 : 12) + extra, lineCap: .round, lineJoin: .round))
            }
        }

        // Sprites back to front, so nearer ones overlap farther ones like in the game.
        var sprites: [(at: CGPoint, image: String, size: CGSize)] = []
        sprites += scene.trees.map { (at: $0, image: "Tree", size: TownLayout.treeSize) }
        sprites += scene.buildings.map { (at: $0.at, image: TownLayout.kinds[$0.kind].asset, size: TownLayout.kinds[$0.kind].size) }
        sprites += scene.centers.map { (at: $0, image: "PokemonCenter", size: TownLayout.centerSize) }
        var resolved: [String: GraphicsContext.ResolvedImage] = [:]
        for sprite in sprites.filter({ visible.contains($0.at) }).sorted(by: { $0.at.y < $1.at.y }) {
            let image = resolved[sprite.image] ?? context.resolve(Image(sprite.image).interpolation(.none))
            resolved[sprite.image] = image
            context.draw(image, in: TownLayout.rect(at: sprite.at, size: sprite.size))
        }

        label("YOU", at: scene.origin, fill: Color(red: 0.22, green: 0.44, blue: 0.78), border: .white, in: &context)
        let target = scene.centers[selectedIndex]
        label(pharmacies[selectedIndex].name, at: CGPoint(x: target.x, y: target.y - TownLayout.centerSize.height), fill: Theme.dialogue, border: Theme.gold, in: &context)
    }

    private func label(_ text: String, at point: CGPoint, fill: Color, border: Color, in context: inout GraphicsContext) {
        let resolved = context.resolve(Text(text).font(Theme.font(13)).foregroundStyle(.white))
        let size = resolved.measure(in: CGSize(width: 300, height: 60))
        let rect = CGRect(x: point.x - size.width / 2 - 8, y: point.y - size.height - 14, width: size.width + 16, height: size.height + 8)
        let shape = Path(roundedRect: rect, cornerRadius: 6)
        context.fill(shape, with: .color(fill))
        context.stroke(shape, with: .color(border), lineWidth: 3)
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Dotted route marching along the streets, and the player walking it over and over.
    private func drawRoute(_ scene: TownScene, camera: Camera, time: TimeInterval, in context: inout GraphicsContext, size: CGSize) {
        camera.apply(to: &context, size: size)
        let points = route.map(scene.projection.point)
        guard points.count > 1 else { return }
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: .color(Theme.red), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [0.1, 14], dashPhase: CGFloat(-time * 20)))

        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        let duration = min(14, max(3, Double(total) * WorldProjection.metersPerPixel / 100))
        let pause = 1.2
        let progress = reduceMotion ? 1 : min(1, time.truncatingRemainder(dividingBy: duration + pause) / duration)
        var remaining = CGFloat(progress) * total
        var at = points.last!
        for (i, leg) in lengths.enumerated() {
            if remaining <= leg, leg > 0 {
                let t = remaining / leg
                at = CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * t, y: points[i].y + (points[i + 1].y - points[i].y) * t)
                break
            }
            remaining -= leg
        }
        // A two-frame hop so the standing sprite looks like it's walking.
        let hop: CGFloat = reduceMotion || Int(time * 6) % 2 == 0 ? 0 : -3
        let walker = context.resolve(Image(player.asset).interpolation(.none))
        context.draw(walker, in: CGRect(x: at.x - 14, y: at.y - 34 + hop, width: 28, height: 38))
    }
}
