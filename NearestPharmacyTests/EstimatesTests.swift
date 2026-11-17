import Foundation
import MapKit
import Testing
@testable import NearestPharmacy

private func date(hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: hour))!
}

private func pharmacy(key: String, distance: CLLocationDistance) -> Pharmacy {
    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 60.17, longitude: 24.94)))
    item.name = key
    return Pharmacy(mapItem: item, distance: distance)
}

struct EstimatesTests {
    @Test func convertsDistanceToStepsCaloriesAndMinutes() {
        #expect(Estimates.steps(750) == 1000)
        #expect(Estimates.calories(750) == 40)
        #expect(Estimates.walkMinutes(800) == 10)
    }

    @Test func neverSaysZeroCaloriesOrMinutes() {
        #expect(Estimates.calories(5) == 1)
        #expect(Estimates.walkMinutes(5) == 1)
    }

    @Test func crowdIsStableAndQuietAtNight() {
        #expect(Crowd(key: "a", at: date(hour: 12)) == Crowd(key: "a", at: date(hour: 12)))
        #expect(Crowd(key: "a", at: date(hour: 3)).people == 0)
        #expect(Crowd(key: "a", at: date(hour: 3)).level == .quiet)
    }

    @Test func waitGrowsWithPeople() {
        for i in 0..<50 {
            let crowd = Crowd(key: "p\(i)", at: date(hour: 17))
            #expect(crowd.waitMinutes == crowd.people * Estimates.minutesPerCustomer)
        }
    }

    @Test func suggestsAFartherPharmacyWhenItIsQuickerOverall() throws {
        let noon = date(hour: 12)
        let keys = (0..<200).map { "p\($0)" }
        let busyKey = try #require(keys.first { Crowd(key: "\($0)@60.17,24.94", at: noon).level == .busy })
        let quietKey = try #require(keys.first { Crowd(key: "\($0)@60.17,24.94", at: noon).level == .quiet })

        let tip = try #require(QuickerAlternative(
            nearest: pharmacy(key: busyKey, distance: 100),
            others: [pharmacy(key: quietKey, distance: 300)],
            at: noon
        ))

        #expect(tip.pharmacy.name == quietKey)
        #expect(tip.extraMeters == 200)
        #expect(tip.minutesSaved > 0)
    }

    @Test func noTipWhenTheNearestIsQuickest() {
        let night = date(hour: 3)
        #expect(QuickerAlternative(nearest: pharmacy(key: "a", distance: 100), others: [pharmacy(key: "b", distance: 5000)], at: night) == nil)
    }
}
