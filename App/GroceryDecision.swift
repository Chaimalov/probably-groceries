import Foundation

enum GroceryDecisionProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, jev

    var id: String { rawValue }
    var title: String { self == .openAI ? "OpenAI Decisions" : "Jev · OpenRouter" }
    var model: String { self == .openAI ? "gpt-6-luna" : "typesafe/jev-1.13" }
    var endpoint: URL {
        URL(string: self == .openAI ? "https://api.openai.com/v1/decisions"
            : "https://openrouter.ai/api/alpha/decisions")!
    }
    var choiceLimit: Int { self == .openAI ? 255 : 24 }
    var questionLimit: Int { self == .openAI ? 400 : 20 }
}

struct GroceryDecisionBatch: Codable, Equatable {
    var listID: UUID
    var revision: String
    var generatedAt: Date
    var provider: GroceryDecisionProvider
    var sponsor: String
    var sponsorID: String
    var recommendations: [UUID]
    // Old batches decode, but lack the evidence digest for this contract.
    var historyRevision: String? = nil
}

struct GroceryDecisionContext {
    struct Event: Codable, Equatable {
        var day: Int
        var quantity: Int
        var unit: String?
    }
    struct ProductEvidence: Codable, Equatable {
        var label: String
        var name: String
        var unit: String?
        var events: [Event]
    }
    struct State: Codable {
        var today: Int
        var products: [ProductEvidence]
        var active: [String]
        var deferred: [String]
        var activeWithoutHistory: [String]
        var deferredWithoutHistory: [String]
    }
    static let version = 2
    static let maxRecommendations = 5
    static let lifetime: TimeInterval = 6 * 3600

    let state: State
    let productIDs: [UUID]
    let eligible: [String]
    private let quantities: [UUID: Int]

    init(data: ShoppingData, listID: UUID, now: Date) {
        // Date and event bounds limit payload size. Every identity with an
        // event in the retained window is eligible, even after one purchase.
        let cutoff = now.addingTimeInterval(-180 * 86400)
        let purchases = data.purchases.filter {
            $0.listID == listID && $0.purchasedAt >= cutoff && $0.purchasedAt <= now && (1...9999).contains($0.quantity)
        }.sorted {
            $0.purchasedAt == $1.purchasedAt ? $0.id.uuidString < $1.id.uuidString : $0.purchasedAt > $1.purchasedAt
        }.prefix(500)
        let groups = ProductLearning.groups(in: data, listID: listID)
        let products = Dictionary(data.products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var representatives: [UUID: UUID] = [:]
        var history: [UUID: [Event]] = [:]
        func day(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 86400)) }
        for purchase in purchases where products[purchase.productID] != nil {
            let id = representatives[purchase.productID] ?? purchase.productID
            for alias in groups[purchase.productID] ?? [purchase.productID] { representatives[alias] = id }
            history[id, default: []].append(Event(day: day(purchase.purchasedAt),
                quantity: purchase.quantity, unit: purchase.unit.map { String($0.prefix(16)) }))
        }

        let active = Set(data.items.filter { $0.listID == listID }.map { representatives[$0.productID] ?? $0.productID })
        let activeNames = Set(active.compactMap { products[$0].map { GroceryCapture.normalize($0.name) } })
        let deferred = Set(data.deferrals.filter { $0.listID == listID && $0.until > now }
            .map { representatives[$0.productID] ?? $0.productID })
        let ids = history.keys.sorted { $0.uuidString < $1.uuidString }
        func namesWithoutHistory(_ ids: Set<UUID>) -> [String] {
            Array(ids.filter { history[$0] == nil }.compactMap {
                products[$0].map { String($0.name.prefix(48)) }
            }.sorted().prefix(100))
        }
        var labels: [UUID: String] = [:]
        var quantities: [UUID: Int] = [:]
        let evidence = ids.enumerated().compactMap { index, id -> ProductEvidence? in
            guard let product = products[id], let events = history[id] else { return nil }
            let label = "p\(index)"
            labels[id] = label
            let unit = product.preferredUnit.map { String($0.prefix(16)) }
            quantities[id] = events.first { $0.unit == unit }?.quantity ?? 1
            return ProductEvidence(label: label, name: String(product.name.prefix(48)), unit: unit, events: events)
        }
        let activeLabels = active.compactMap { labels[$0] }.sorted()
        let deferredLabels = deferred.compactMap { labels[$0] }.sorted()
        let suppressed = active.union(deferred)
        let deferredNames = Set(deferred.compactMap { products[$0].map { GroceryCapture.normalize($0.name) } })
        self.state = State(today: day(now), products: evidence, active: activeLabels, deferred: deferredLabels,
            activeWithoutHistory: namesWithoutHistory(active), deferredWithoutHistory: namesWithoutHistory(deferred))
        self.productIDs = ids
        self.eligible = ids.filter {
            guard !suppressed.contains($0), let product = products[$0] else { return false }
            let name = GroceryCapture.normalize(product.name)
            return !activeNames.contains(name) && !deferredNames.contains(name)
        }.compactMap { labels[$0] }
        self.quantities = quantities
    }

    func productID(for label: String) -> UUID? {
        guard let index = Int(label.dropFirst()), label == "p\(index)", productIDs.indices.contains(index) else { return nil }
        return productIDs[index]
    }

    func revisionData(includeSuppressions: Bool = true) throws -> Data {
        struct Revision: Encodable {
            let version = GroceryDecisionContext.version
            var productIDs: [UUID]
            var state: State
            var eligible: [String]?
        }
        var input = state
        if !includeSuppressions {
            input.active = []
            input.deferred = []
            input.activeWithoutHistory = []
            input.deferredWithoutHistory = []
        }
        return try Self.encoder.encode(Revision(productIDs: productIDs, state: input, eligible: includeSuppressions ? eligible : nil))
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    func accepts(_ batch: GroceryDecisionBatch, listID: UUID, historyRevision: String?,
                 provider: GroceryDecisionProvider?, now: Date) -> Bool {
        batch.listID == listID && historyRevision != nil && batch.historyRevision == historyRevision
            && (provider == nil || batch.provider == provider)
            && batch.generatedAt <= now && now.timeIntervalSince(batch.generatedAt) < Self.lifetime
    }

    func suggestions(from batch: GroceryDecisionBatch, in data: ShoppingData) -> [Suggestion] {
        let allowed = Set(eligible.compactMap(productID(for:)))
        let products = Dictionary(data.products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var names: Set<String> = []
        return batch.recommendations.prefix(Self.maxRecommendations).compactMap { id in
            guard allowed.contains(id), let product = products[id], let quantity = quantities[id],
                  names.insert(GroceryCapture.normalize(product.name)).inserted else { return nil }
            return Suggestion(product: product, quantity: quantity)
        }
    }
}

enum GroceryDecisionError: Error, LocalizedError {
    case invalidResponse, malformedResponse, refused, unauthorized, quota, rateLimited(TimeInterval?)
    case rejectedRequest, inputTooLarge, network, unavailable, keyStorage, invalidKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "התשובה מהספק לא תאמה את הבקשה."
        case .malformedResponse: return "לא הצלחנו לקרוא את התשובה מהספק."
        case .refused: return "הספק לא סיפק החלטה עבור הרשימה."
        case .unauthorized: return "כדאי לבדוק את מפתח ה־API ואת הגישה למודל אצל הספק."
        case .quota: return "מכסת הבקשות נוצלה. אפשר לנסות שוב מחר."
        case .rateLimited: return "הספק הגביל את השימוש. אפשר לנסות שוב מאוחר יותר."
        case .rejectedRequest: return "הספק דחה את הבקשה. כדאי לבדוק את הגדרות החיבור והחיוב."
        case .inputTooLarge: return "היסטוריית הקניות גדולה מהמגבלה של הספק."
        case .network: return "החיבור נקטע. ננסה שוב כשהרשת תהיה זמינה."
        case .unavailable: return "הספק אינו זמין כרגע. אפשר לנסות שוב מאוחר יותר."
        case .keyStorage: return "לא הצלחנו לעדכן את המפתח המאובטח במכשיר."
        case .invalidKey: return "יש להזין מפתח API תקין ללא רווחים."
        }
    }
}
