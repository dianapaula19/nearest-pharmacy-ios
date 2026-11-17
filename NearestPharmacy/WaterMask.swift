import MapKit
import UIKit

/// The town's water, taken from an Apple Maps snapshot of the same area: every pixel that is water on
/// the regular map becomes the game's water blue, everything else transparent.
enum WaterMask {
    /// Image and the world rectangle (see `WorldProjection`) it covers.
    struct Layer {
        let image: CGImage
        let rect: CGRect
    }

    static let gameWater = (r: UInt8(88), g: UInt8(144), b: UInt8(240))

    static func make(around projection: WorldProjection, covering world: CGRect) async throws -> Layer {
        let options = MKMapSnapshotter.Options()
        let mpp = WorldProjection.metersPerPixel
        options.region = MKCoordinateRegion(
            center: projection.center.coordinate,
            latitudinalMeters: world.height * mpp,
            longitudinalMeters: world.width * mpp
        )
        options.size = world.size
        options.scale = 1
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        guard let source = snapshot.image.cgImage, let image = recolor(source) else { throw CocoaError(.coderInvalidValue) }
        // The snapshot is centred on the projection centre, which is world (0, 0).
        return Layer(image: image, rect: CGRect(x: -world.width / 2, y: -world.height / 2, width: world.width, height: world.height))
    }

    /// Water on Apple's light map is clearly bluer than it is red or green; land, parks and roads aren't.
    static func isWater(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        Int(b) - Int(r) > 45 && Int(b) > Int(g) + 10
    }

    static func recolor(_ source: CGImage) -> CGImage? {
        let width = source.width, height = source.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            if isWater(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2]) {
                (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = (gameWater.r, gameWater.g, gameWater.b, 255)
            } else {
                (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = (0, 0, 0, 0)
            }
        }
        return context.makeImage()
    }
}
