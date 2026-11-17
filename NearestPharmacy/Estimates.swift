import CoreLocation
import Foundation

// Walking figures are estimates for an average adult; crowd levels are simulated, not real data.
enum Estimates {
    static let strideMeters = 0.75
    static let kcalPerStep = 0.04
    static let walkMetersPerMinute = 80.0 // ~4.8 km/h
    static let minutesPerCustomer = 2

    static func steps(_ meters: CLLocationDistance) -> Int { Int((meters / strideMeters).rounded()) }
    static func calories(_ meters: CLLocationDistance) -> Int { max(1, Int((Double(steps(meters)) * kcalPerStep).rounded())) }
    static func walkMinutes(_ meters: CLLocationDistance) -> Int { max(1, Int((meters / walkMetersPerMinute).rounded())) }
}

struct Crowd: Equatable {
    enum Level { case quiet, moderate, busy }

    let people: Int
    let waitMinutes: Int
    var level: Level { people <= 2 ? .quiet : people <= 5 ? .moderate : .busy }

    // Typical pharmacy footfall by hour (0–23): lunch and after-work peaks.
    private static let hourly: [Double] = [0, 0, 0, 0, 0, 0, 0.1, 0.2, 0.4, 0.5, 0.6, 0.8, 1, 0.8, 0.6, 0.6, 0.8, 1, 0.9, 0.6, 0.4, 0.3, 0.2, 0.1]

    /// Simulated queue: each pharmacy has its own baseline popularity, scaled by time of day.
    init(key: String, at date: Date = .now, calendar: Calendar = .current) {
        let popularity = 0.25 + Self.seeded(key) * 0.75
        people = Int((popularity * Self.hourly[calendar.component(.hour, from: date)] * 9).rounded())
        waitMinutes = people * Estimates.minutesPerCustomer
    }

    /// Stable pseudo-random number in [0, 1) per key (FNV-1a), so a pharmacy keeps its "personality".
    private static func seeded(_ key: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Double(hash) / 4_294_967_296
    }
}

struct QuickerAlternative {
    let pharmacy: Pharmacy
    let extraMeters: CLLocationDistance
    let minutesSaved: Int

    /// The pharmacy where you'd be served soonest (walk + queue), if that's not the nearest one.
    init?(nearest: Pharmacy, others: [Pharmacy], at date: Date = .now) {
        func total(_ p: Pharmacy) -> Int { Estimates.walkMinutes(p.distance) + Crowd(key: p.crowdKey, at: date).waitMinutes }
        guard let best = others.min(by: { total($0) < total($1) }), total(best) < total(nearest) else { return nil }
        pharmacy = best
        extraMeters = best.distance - nearest.distance
        minutesSaved = total(nearest) - total(best)
    }
}
