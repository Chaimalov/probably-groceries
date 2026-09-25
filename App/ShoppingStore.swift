import Combine
import Foundation

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var data: ShoppingData
    @Published private(set) var selectedListID: UUID

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
        let savedID = UserDefaults.standard.string(forKey: "selectedShoppingListID")
            .flatMap(UUID.init(uuidString:))
        selectedListID = data.lists.contains(where: { $0.id == savedID })
            ? savedID! : data.lists.first?.id ?? ShoppingList.defaultID
        if let index = data.lists.firstIndex(where: {
            $0.id == ShoppingList.defaultID && $0.name == "Groceries"
        }) {
            data.lists[index].name = "קניות"
            persist()
        }
    }

    var currentList: ShoppingList {
        data.lists.first { $0.id == selectedListID }
            ?? ShoppingList(id: ShoppingList.defaultID, name: "קניות")
    }

    func selectList(_ id: UUID) {
        guard data.lists.contains(where: { $0.id == id }) else { return }
        selectedListID = id
        UserDefaults.standard.set(id.uuidString, forKey: "selectedShoppingListID")
    }

    func addList(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let list = ShoppingList(id: UUID(), name: name)
        data.lists.append(list)
        persist()
        selectList(list.id)
    }

    func renameCurrentList(to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = data.lists.firstIndex(where: { $0.id == selectedListID }) else { return }
        data.lists[index].name = name
        persist()
    }

    var items: [ShoppingItem] {
        let positions = ShoppingRouteOrder.positions(from: data.purchases.filter { $0.listID == selectedListID })
        return data.items.filter { $0.listID == selectedListID }.sorted { left, right in
            switch (positions[left.productID], positions[right.productID]) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if left.addedAt != right.addedAt { return left.addedAt < right.addedAt }
                return left.id.uuidString < right.id.uuidString
            }
        }
    }
    var purchases: [Purchase] {
        data.purchases.filter { $0.listID == selectedListID }
            .sorted { $0.purchasedAt > $1.purchasedAt }
    }
    var recentPurchases: [Purchase] {
        Array(purchases.prefix(5))
    }

    func product(for id: UUID) -> Product? { data.products.first { $0.id == id } }

    func matchingProducts(_ query: String) -> [Product] {
        let value = Self.normalize(query)
        guard !value.isEmpty else { return [] }
        return data.products.filter { Self.normalize($0.name).localizedStandardContains(value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func add(name: String, quantity: Int, category: String? = nil,
             department: String? = nil, urgent: Bool = false) {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }
        let normalized = Self.normalize(displayName)
        let productID: UUID
        if let existing = data.products.first(where: { Self.normalize($0.name) == normalized }) {
            productID = existing.id
            if let category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let index = data.products.firstIndex(where: { $0.id == productID }) {
                data.products[index].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let department, !department.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let index = data.products.firstIndex(where: { $0.id == productID }) {
                data.products[index].department = department.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            let product = Product(id: UUID(), name: displayName, usualQuantity: max(1, quantity),
                                  category: category?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  department: department?.trimmingCharacters(in: .whitespacesAndNewlines))
            data.products.append(product)
            productID = product.id
        }
        if let index = data.items.firstIndex(where: {
            $0.productID == productID && $0.listID == selectedListID
        }) {
            data.items[index].quantity += max(1, quantity)
            data.items[index].isUrgent = data.items[index].isUrgent || urgent
        } else {
            data.items.append(ShoppingItem(id: UUID(), productID: productID,
                                           quantity: max(1, quantity), addedAt: .now,
                                           listID: selectedListID, isUrgent: urgent))
        }
        data.deferrals.removeAll { $0.productID == productID && $0.listID == selectedListID }
        persist()
    }

    func add(_ suggestion: Suggestion) {
        add(name: suggestion.product.name, quantity: suggestion.quantity)
    }

    func remove(_ item: ShoppingItem) {
        data.items.removeAll { $0.id == item.id }
        persist()
    }

    func setGrouping(for productID: UUID, department: String?, category: String?) {
        guard let index = data.products.firstIndex(where: { $0.id == productID }) else { return }
        let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDepartment = department?.trimmingCharacters(in: .whitespacesAndNewlines)
        data.products[index].category = trimmedCategory?.isEmpty == false ? trimmedCategory : nil
        data.products[index].department = trimmedDepartment?.isEmpty == false ? trimmedDepartment : nil
        persist()
    }

    func toggleUrgent(_ item: ShoppingItem) {
        guard let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        data.items[index].isUrgent.toggle()
        persist()
    }

    var categories: [String] {
        Array(Set(data.products.compactMap(\.category)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var departments: [String] {
        Array(Set(data.products.compactMap(\.department)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func updateQuantity(of item: ShoppingItem, to quantity: Int) {
        guard (1...9999).contains(quantity),
              let index = data.items.firstIndex(where: { $0.id == item.id }) else { return }
        data.items[index].quantity = quantity
        persist()
    }

    func buy(_ item: ShoppingItem) {
        guard let current = data.items.first(where: { $0.id == item.id }) else { return }
        data.items.removeAll { $0.id == current.id }
        data.purchases.append(Purchase(id: UUID(), productID: current.productID,
                                       quantity: current.quantity, purchasedAt: .now,
                                       sourceItemID: current.id, listID: current.listID,
                                       wasUrgent: current.isUrgent))
        updateUsualQuantity(for: current.productID)
        persist()
    }

    func correctQuantity(of purchase: Purchase, to quantity: Int) {
        guard (1...9999).contains(quantity),
              let index = data.purchases.firstIndex(where: { $0.id == purchase.id }) else { return }
        data.purchases[index].quantity = quantity
        updateUsualQuantity(for: purchase.productID)
        persist()
    }

    func undo(_ purchase: Purchase) {
        guard let current = data.purchases.first(where: { $0.id == purchase.id }) else { return }
        data.purchases.removeAll { $0.id == purchase.id }
        if let index = data.items.firstIndex(where: {
            $0.productID == current.productID && $0.listID == current.listID
        }) {
            data.items[index].quantity += current.quantity
            data.items[index].isUrgent = data.items[index].isUrgent || current.wasUrgent
        } else {
            data.items.append(ShoppingItem(id: current.sourceItemID,
                                           productID: current.productID,
                                           quantity: current.quantity, addedAt: .now,
                                           listID: current.listID, isUrgent: current.wasUrgent))
        }
        updateUsualQuantity(for: current.productID)
        persist()
    }

    func deferSuggestion(_ suggestion: Suggestion) {
        data.deferrals.removeAll { $0.productID == suggestion.id && $0.listID == selectedListID }
        data.deferrals.append(Deferral(productID: suggestion.id,
                                       until: Calendar.current.date(byAdding: .day, value: 3, to: .now)!,
                                       listID: selectedListID))
        persist()
    }

    var predictionEvaluations: [PredictionEvaluation] {
        PredictionEngine.evaluate(data, listID: selectedListID)
    }

    var suggestions: [Suggestion] {
        let positions = ShoppingRouteOrder.positions(from: data.purchases.filter { $0.listID == selectedListID })
        return predictionEvaluations.compactMap(\.suggestion).sorted { left, right in
            switch (positions[left.id], positions[right.id]) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if left.progress != right.progress { return left.progress > right.progress }
                return left.product.name.localizedStandardCompare(right.product.name) == .orderedAscending
            }
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func updateUsualQuantity(for productID: UUID) {
        guard let index = data.products.firstIndex(where: { $0.id == productID }) else { return }
        data.products[index].usualQuantity = data.purchases
            .filter { $0.productID == productID }
            .max(by: { $0.purchasedAt < $1.purchasedAt })?.quantity ?? 1
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
