import Foundation

/// Learns aisle order from the exact times items were checked off on each trip.
enum ShoppingRouteOrder {
    static func positions(from purchases: [Purchase]) -> [UUID: Double] {
        let events = purchases.sorted {
            if $0.purchasedAt != $1.purchasedAt { return $0.purchasedAt < $1.purchasedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var trips: [[Purchase]] = []
        for event in events {
            if let last = trips.last?.last,
               event.purchasedAt.timeIntervalSince(last.purchasedAt) < 12 * 3600 {
                trips[trips.count - 1].append(event)
            } else {
                trips.append([event])
            }
        }

        var observations: [UUID: [(position: Double, trip: Int)]] = [:]
        for (tripIndex, trip) in trips.enumerated() {
            // A second check-off of the same product on one trip is not a second aisle.
            var seen = Set<UUID>()
            let orderedProducts = trip.compactMap { event -> UUID? in
                seen.insert(event.productID).inserted ? event.productID : nil
            }
            for (index, productID) in orderedProducts.enumerated() {
                let position = orderedProducts.count == 1
                    ? 0.5 : Double(index) / Double(orderedProducts.count - 1)
                observations[productID, default: []].append((position, tripIndex))
            }
        }

        return observations.mapValues { values in
            let recent = values.suffix(5)
            let weights = recent.map { Double($0.trip + 1) }
            return zip(recent, weights).reduce(0.0) { $0 + $1.0.position * $1.1 }
                / weights.reduce(0, +)
        }
    }
}
