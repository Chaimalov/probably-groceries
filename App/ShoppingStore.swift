import Combine
import Foundation

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var data: ShoppingData

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("shopping.json")
        if let bytes = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(ShoppingData.self, from: bytes) {
            data = saved
        } else {
            data = ShoppingData()
        }
    }

    var items: [ShoppingItem] { data.items.sorted { $0.addedAt < $1.addedAt } }
    var recentPurchases: [Purchase] {
        Array(data.purchases.sorted { $0.purchasedAt > $1.purchasedAt }.prefix(5))
    }

    func product(for id: UUID) -> Product? { data.products.first { $0.id == id } }

    func matchingProducts(_ query: String) -> [Product] {
        let value = Self.normalize(query)
        guard !value.isEmpty else { return [] }
        return data.products.filter { Self.normalize($0.name).localizedStandardContains(value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func add(name: String, quantity: Int) {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        let normalized = Self.normalize(displayName)
        let productID: UUID
        if let existing = data.products.first(where: { Self.normalize($0.name) == normalized }) {
            productID = existing.id
        } else {
            let product = Product(id: UUID(), name: displayName, usualQuantity: max(1, quantity))
            data.products.append(product)
            productID = product.id
        }
        if let index = data.items.firstIndex(where: { $0.productID == productID }) {
            data.items[index].quantity += max(1, quantity)
        } else {
            data.items.append(ShoppingItem(id: UUID(), productID: productID,
                                           quantity: max(1, quantity), addedAt: .now))
        }
        data.deferrals.removeAll { $0.productID == productID }
        persist()
    }

    func add(_ suggestion: Suggestion) {
        add(name: suggestion.product.name, quantity: suggestion.quantity)
    }

    func remove(_ item: ShoppingItem) {
        data.items.removeAll { $0.id == item.id }
        persist()
    }

    func buy(_ item: ShoppingItem) {
        guard data.items.contains(where: { $0.id == item.id }) else { return }
        data.items.removeAll { $0.id == item.id }
        data.purchases.append(Purchase(id: UUID(), productID: item.productID,
                                       quantity: item.quantity, purchasedAt: .now,
                                       sourceItemID: item.id))
        if let index = data.products.firstIndex(where: { $0.id == item.productID }) {
            data.products[index].usualQuantity = item.quantity
        }
        persist()
    }

    func undo(_ purchase: Purchase) {
        guard data.purchases.contains(where: { $0.id == purchase.id }) else { return }
        data.purchases.removeAll { $0.id == purchase.id }
        if !data.items.contains(where: { $0.productID == purchase.productID }) {
            data.items.append(ShoppingItem(id: purchase.sourceItemID,
                                           productID: purchase.productID,
                                           quantity: purchase.quantity, addedAt: .now))
        }
        persist()
    }

    func deferSuggestion(_ suggestion: Suggestion) {
        data.deferrals.removeAll { $0.productID == suggestion.id }
        data.deferrals.append(Deferral(productID: suggestion.id,
                                       until: Calendar.current.date(byAdding: .day, value: 3, to: .now)!))
        persist()
    }

    var suggestions: [Suggestion] {
        let now = Date.now
        let activeIDs = Set(data.items.map(\.productID))
        return data.products.compactMap { product -> Suggestion? in
            guard !activeIDs.contains(product.id),
                  !data.deferrals.contains(where: { $0.productID == product.id && $0.until > now })
            else { return nil }
            let dates = data.purchases.filter { $0.productID == product.id }
                .map(\.purchasedAt).sorted()
            guard dates.count >= 3, let latest = dates.last else { return nil }
            let intervals = zip(dates.dropFirst(), dates).map { pair in
                pair.0.timeIntervalSince(pair.1) / 86_400
            }.filter { $0 >= 0.5 }
            guard !intervals.isEmpty else { return nil }
            let ordered = intervals.sorted()
            let typical = ordered[ordered.count / 2]
            let progress = now.timeIntervalSince(latest) / 86_400 / max(typical, 1)
            guard progress >= 0.8 else { return nil }
            return Suggestion(product: product, quantity: product.usualQuantity,
                              tier: progress >= 1.05 ? .likely : .maybe,
                              progress: progress)
        }.sorted { $0.progress > $1.progress }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Could not save the shopping list: \(error)")
        }
    }
}
