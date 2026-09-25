import Foundation

enum PredictionEngine {
    static func evaluate(_ data: ShoppingData, now: Date = .now) -> [PredictionEvaluation] {
        let activeIDs = Set(data.items.map(\.productID))
        return data.products.map { product in
            let purchases = data.purchases.filter { $0.productID == product.id && $0.purchasedAt <= now }
                .sorted { $0.purchasedAt < $1.purchasedAt }
            let recentQuantities = purchases.suffix(5).map(\.quantity).filter { $0 > 0 }.sorted()
            let quantity = recentQuantities.isEmpty
                ? max(1, product.usualQuantity)
                : recentQuantities[recentQuantities.count / 2]
            let trips = purchases.reduce(into: [Purchase]()) { result, purchase in
                // Repeated check-offs during one trip are one timing signal.
                if let previous = result.last,
                   purchase.purchasedAt.timeIntervalSince(previous.purchasedAt) < 12 * 3600 {
                    result[result.count - 1] = purchase
                } else {
                    result.append(purchase)
                }
            }
            let latest = trips.last?.purchasedAt
            let age = latest.map { max(0, now.timeIntervalSince($0) / 86_400) }
            let intervals = zip(trips.dropFirst(), trips).map {
                $0.0.purchasedAt.timeIntervalSince($0.1.purchasedAt) / 86_400
            }.suffix(5).map { min(max($0, 0.5), 120) }.sorted()
            let typical = intervals.count >= 2 ? intervals[intervals.count / 2] : nil
            let progress = age.flatMap { days in typical.map { days / max($0, 1) } }

            let reason: String
            let tier: Suggestion.Tier?
            if activeIDs.contains(product.id) {
                reason = "Already on the list"
                tier = nil
            } else if let deferred = data.deferrals.first(where: { $0.productID == product.id && $0.until > now }) {
                reason = "Deferred until \(deferred.until.formatted(date: .abbreviated, time: .omitted))"
                tier = nil
            } else if trips.count < 3 {
                reason = "Needs three separate shopping trips"
                tier = nil
            } else if let progress, progress >= 1.05 {
                reason = "Recurring purchase is due"
                tier = .likely
            } else if let progress, progress >= 0.8 {
                reason = "Recurring purchase is approaching"
                tier = .maybe
            } else {
                reason = "Not due yet"
                tier = nil
            }
            return PredictionEvaluation(product: product, purchaseCount: purchases.count,
                                        distinctTripCount: trips.count, intervalDays: typical,
                                        daysSincePurchase: age, quantity: quantity,
                                        progress: progress, tier: tier, reason: reason)
        }
    }
}
