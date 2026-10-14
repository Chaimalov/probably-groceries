import Foundation

enum ShoppingSession {
    // Bookkeeping only. No timer, list reset or synthetic purchase.
    static let inactivityThreshold: TimeInterval = 3 * 3600
    static func groups(_ purchases: [Purchase]) -> [[Purchase]] {
        var sessions: [[Purchase]] = []
        let ordered = purchases.sorted {
            if $0.listID != $1.listID { return $0.listID.uuidString < $1.listID.uuidString }
            if $0.purchasedAt != $1.purchasedAt { return $0.purchasedAt < $1.purchasedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for purchase in ordered {
            if let previous = sessions.last?.last, previous.listID == purchase.listID,
               purchase.purchasedAt.timeIntervalSince(previous.purchasedAt) < inactivityThreshold {
                sessions[sessions.count - 1].append(purchase)
            } else { sessions.append([purchase]) }
        }
        return sessions
    }
}
