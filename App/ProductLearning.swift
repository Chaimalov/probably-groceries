import Foundation

struct ProductLearningLink: Codable, Equatable {
    var listID: UUID
    var targetID: UUID
    var sourceName: String
    var targetName: String
    var sourceUnit: String?
    var targetUnit: String?
    var model: String
    var policyVersion: String
    var probability: Double
    var confidence: Double
    var createdAt: Date
}

enum ProductLearning {
    static func candidates(for source: Product, in data: ShoppingData, listID: UUID) -> [Product] {
        let scoped = Set(data.items.filter { $0.listID == listID }.map(\.productID)
            + data.purchases.filter { $0.listID == listID }.map(\.productID))
        let left = normalized(source.name)
        let words = Set(left.split(separator: " "))
        return data.products.filter { $0.id != source.id && scoped.contains($0.id) }
            .map { candidate -> (Product, Double) in
                let right = normalized(candidate.name)
                let distance = Double(editDistance(left, right)) / Double(max(1, max(left.count, right.count)))
                let overlaps = !words.isDisjoint(with: Set(right.split(separator: " ")))
                return (candidate, overlaps ? min(distance, 0.5) : distance)
            }
            .filter { $0.1 <= 0.55 }
            .sorted { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 < $1.1 }
            .prefix(8).map(\.0)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "he_IL"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left.prefix(120)), b = Array(right.prefix(120))
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var row = [i + 1]
            for (j, other) in b.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (character == other ? 0 : 1)))
            }
            previous = row
        }
        return previous[b.count]
    }

    static func groups(in data: ShoppingData, listID: UUID) -> [UUID: Set<UUID>] {
        let products = Dictionary(data.products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scoped = Set(data.items.filter { $0.listID == listID }.map(\.productID)
            + data.purchases.filter { $0.listID == listID }.map(\.productID)
            + data.deferrals.filter { $0.listID == listID }.map(\.productID))
        var adjacency: [UUID: Set<UUID>] = [:]
        for source in data.products where scoped.contains(source.id) {
            for link in source.learningLinks ?? [] where link.listID == listID {
                guard scoped.contains(link.targetID), let target = products[link.targetID],
                      source.name == link.sourceName, target.name == link.targetName,
                      source.preferredUnit == link.sourceUnit, target.preferredUnit == link.targetUnit,
                      link.sourceUnit == link.targetUnit,
                      link.policyVersion == "product-identity-v1",
                      link.probability >= 0.98, link.confidence >= 0.9 else { continue }
                adjacency[source.id, default: []].insert(target.id)
                adjacency[target.id, default: []].insert(source.id)
            }
        }
        var result: [UUID: Set<UUID>] = [:]
        for id in products.keys where result[id] == nil {
            var group: Set<UUID> = [], pending = [id]
            while let next = pending.popLast() {
                guard group.insert(next).inserted else { continue }
                pending.append(contentsOf: adjacency[next] ?? [])
            }
            for member in group { result[member] = group }
        }
        return result
    }

    static func representative(of ids: Set<UUID>, in data: ShoppingData, listID: UUID, now: Date = .now) -> UUID? {
        // Keep the name used in the latest purchase, with stable tie-breaking.
        data.purchases.filter { $0.listID == listID && ids.contains($0.productID) && $0.purchasedAt <= now }
            .sorted { $0.purchasedAt == $1.purchasedAt ? $0.id.uuidString < $1.id.uuidString : $0.purchasedAt > $1.purchasedAt }
            .first?.productID ?? ids.sorted { $0.uuidString < $1.uuidString }.first
    }
}
