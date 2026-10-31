import Foundation

// No chat/generation interface: adapters can only answer bounded yes/no questions.
enum GroceryDecisionProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, jev
    var id: String { rawValue }
    var title: String { self == .openAI ? "OpenAI Decisions" : "Jev · TypeSafe" }
    var model: String { self == .openAI ? "gpt-6-luna" : "jev-latest" }
    var endpoint: URL {
        URL(string: self == .openAI ? "https://api.openai.com/v1/decisions" : "https://api.typesafe.ai/v1/systemone")!
    }
}

struct GroceryDecisionCandidate: Codable, Equatable {
    struct Event: Codable, Equatable { var daysAgo: Int; var quantity: Int }
    var id: UUID
    var name: String
    var unit: String?
    var quantity: Int
    var events: [Event]
}

struct GroceryDecisionBatch: Codable, Equatable {
    var listID: UUID
    var revision: String
    var generatedAt: Date
    var provider: GroceryDecisionProvider
    var sponsor: String
    var sponsorID: String
    var recommendations: [UUID]
}

enum GroceryDecisionContract {
    static let maxCandidates = 32
    static let threshold = 0.85 // Conservative starting policy, not calibrated accuracy.
    static let lifetime: TimeInterval = 6 * 3600

    static func candidates(in data: ShoppingData, listID: UUID, now: Date) -> [GroceryDecisionCandidate] {
        let groups = ProductLearning.groups(in: data, listID: listID)
        let evaluations = PredictionEngine.evaluate(data, now: now, listID: listID)
        let active = Set(data.items.filter { $0.listID == listID }.map(\.productID))
        let deferred = Set(data.deferrals.filter { $0.listID == listID && $0.until > now }.map(\.productID))
        return evaluations.sorted { $0.id.uuidString < $1.id.uuidString }.compactMap { evaluation -> GroceryDecisionCandidate? in
            let product = evaluation.product
            let identities = groups[product.id] ?? [product.id]
            guard evaluation.distinctTripCount >= 3,
                  active.isDisjoint(with: identities), deferred.isDisjoint(with: identities),
                  ProductLearning.representative(of: identities, in: data, listID: listID, now: now) == product.id
            else { return nil }
            let events = data.purchases.filter {
                $0.listID == listID && identities.contains($0.productID) && $0.purchasedAt <= now
            }.sorted { $0.purchasedAt < $1.purchasedAt }.suffix(6).map {
                GroceryDecisionCandidate.Event(daysAgo: max(0, Int(now.timeIntervalSince($0.purchasedAt) / 86400)),
                                               quantity: max(1, $0.quantity))
            }
            return GroceryDecisionCandidate(id: product.id, name: String(product.name.prefix(120)),
                unit: product.preferredUnit.map { String($0.prefix(40)) },
                quantity: evaluation.quantity, events: events)
        }.prefix(maxCandidates).map { $0 }
    }

    // Local-only source revision includes corrections, aliases, active items and deferrals.
    // Stable ordering prevents different CloudKit arrival order from invalidating results.
    static func revisionData(_ data: ShoppingData, listID: UUID, now: Date) throws -> Data {
        struct ProductRevision: Encodable {
            var id: UUID; var name: String; var unit: String?; var quantity: Int
            var links: [ProductLearningLink]
        }
        struct EventRevision: Encodable {
            var id: UUID; var productID: UUID; var quantity: Int; var at: Date
        }
        struct Revision: Encodable {
            var day: Int; var products: [ProductRevision]; var items: [EventRevision]
            var purchases: [EventRevision]; var deferrals: [Deferral]
        }
        let purchases = data.purchases.filter { $0.listID == listID }.sorted { $0.id.uuidString < $1.id.uuidString }
        let items = data.items.filter { $0.listID == listID }.sorted { $0.id.uuidString < $1.id.uuidString }
        let deferrals = data.deferrals.filter { $0.listID == listID }.sorted { $0.productID.uuidString < $1.productID.uuidString }
        let ids = Set(purchases.map(\.productID) + items.map(\.productID) + deferrals.map(\.productID))
        let products = data.products.filter { ids.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            ProductRevision(id: $0.id, name: $0.name, unit: $0.preferredUnit, quantity: $0.usualQuantity,
                links: ($0.learningLinks ?? []).filter { $0.listID == listID }.sorted { $0.targetID.uuidString < $1.targetID.uuidString })
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Revision(day: Int(now.timeIntervalSince1970 / 86400), products: products,
            items: items.map { EventRevision(id: $0.id, productID: $0.productID, quantity: $0.quantity, at: $0.addedAt) },
            purchases: purchases.map { EventRevision(id: $0.id, productID: $0.productID, quantity: $0.quantity, at: $0.purchasedAt) },
            deferrals: deferrals))
    }

    static func selected(_ probabilities: [UUID: Double], candidates: [GroceryDecisionCandidate]) throws -> [UUID] {
        guard Set(probabilities.keys).isSubset(of: Set(candidates.map(\.id))),
              probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw GroceryDecisionError.invalidResponse
        }
        return candidates.filter { (probabilities[$0.id] ?? 0) >= threshold }.map(\.id)
    }
}

enum GroceryDecisionError: Error, LocalizedError {
    case invalidResponse, unauthorized, quota, unavailable, keyStorage, invalidKey
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "הספק החזיר תשובה שלא ניתן להשתמש בה."
        case .unauthorized: return "המפתח אינו מורשה. כדאי לבדוק אותו ואת הגישה למודל אצל הספק."
        case .quota: return "הגענו למגבלת השימוש. אפשר לבדוק את המכסה אצל הספק."
        case .unavailable: return "לא הצלחנו להגיע לספק. אפשר לנסות שוב מאוחר יותר."
        case .keyStorage: return "לא הצלחנו לעדכן את המפתח המאובטח במכשיר."
        case .invalidKey: return "יש להזין מפתח API תקין ללא רווחים."
        }
    }
}
