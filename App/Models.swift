import Foundation

struct Product: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var usualQuantity: Int
    var category: String? = nil
}

struct ShoppingList: Codable, Identifiable, Hashable {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var id: UUID
    var name: String
}

struct ShoppingItem: Codable, Identifiable, Hashable {
    var id: UUID
    var productID: UUID
    var quantity: Int
    var addedAt: Date
    var listID: UUID = ShoppingList.defaultID
    var isUrgent: Bool = false

    enum CodingKeys: String, CodingKey { case id, productID, quantity, addedAt, listID, isUrgent }
    init(id: UUID, productID: UUID, quantity: Int, addedAt: Date,
         listID: UUID = ShoppingList.defaultID, isUrgent: Bool = false) {
        self.id = id; self.productID = productID; self.quantity = quantity
        self.addedAt = addedAt; self.listID = listID; self.isUrgent = isUrgent
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        productID = try c.decode(UUID.self, forKey: .productID)
        quantity = try c.decode(Int.self, forKey: .quantity)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        listID = try c.decodeIfPresent(UUID.self, forKey: .listID) ?? ShoppingList.defaultID
        isUrgent = try c.decodeIfPresent(Bool.self, forKey: .isUrgent) ?? false
    }
}

struct Purchase: Codable, Identifiable, Hashable {
    var id: UUID
    var productID: UUID
    var quantity: Int
    var purchasedAt: Date
    var sourceItemID: UUID
    var listID: UUID = ShoppingList.defaultID
    var wasUrgent: Bool = false

    enum CodingKeys: String, CodingKey { case id, productID, quantity, purchasedAt, sourceItemID, listID, wasUrgent }
    init(id: UUID, productID: UUID, quantity: Int, purchasedAt: Date,
         sourceItemID: UUID, listID: UUID = ShoppingList.defaultID, wasUrgent: Bool = false) {
        self.id = id; self.productID = productID; self.quantity = quantity
        self.purchasedAt = purchasedAt; self.sourceItemID = sourceItemID
        self.listID = listID; self.wasUrgent = wasUrgent
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        productID = try c.decode(UUID.self, forKey: .productID)
        quantity = try c.decode(Int.self, forKey: .quantity)
        purchasedAt = try c.decode(Date.self, forKey: .purchasedAt)
        sourceItemID = try c.decode(UUID.self, forKey: .sourceItemID)
        listID = try c.decodeIfPresent(UUID.self, forKey: .listID) ?? ShoppingList.defaultID
        wasUrgent = try c.decodeIfPresent(Bool.self, forKey: .wasUrgent) ?? false
    }
}

struct Deferral: Codable, Hashable {
    var productID: UUID
    var until: Date
    var listID: UUID = ShoppingList.defaultID

    enum CodingKeys: String, CodingKey { case productID, until, listID }
    init(productID: UUID, until: Date, listID: UUID = ShoppingList.defaultID) {
        self.productID = productID; self.until = until; self.listID = listID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productID = try c.decode(UUID.self, forKey: .productID)
        until = try c.decode(Date.self, forKey: .until)
        listID = try c.decodeIfPresent(UUID.self, forKey: .listID) ?? ShoppingList.defaultID
    }
}

struct ShoppingData: Codable {
    var lists: [ShoppingList] = [ShoppingList(id: ShoppingList.defaultID, name: "Groceries")]
    var products: [Product] = []
    var items: [ShoppingItem] = []
    var purchases: [Purchase] = []
    var deferrals: [Deferral] = []

    enum CodingKeys: String, CodingKey { case lists, products, items, purchases, deferrals }
    init(lists: [ShoppingList] = [ShoppingList(id: ShoppingList.defaultID, name: "Groceries")],
         products: [Product] = [], items: [ShoppingItem] = [],
         purchases: [Purchase] = [], deferrals: [Deferral] = []) {
        self.lists = lists; self.products = products; self.items = items
        self.purchases = purchases; self.deferrals = deferrals
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lists = try c.decodeIfPresent([ShoppingList].self, forKey: .lists)
            ?? [ShoppingList(id: ShoppingList.defaultID, name: "Groceries")]
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        items = try c.decodeIfPresent([ShoppingItem].self, forKey: .items) ?? []
        purchases = try c.decodeIfPresent([Purchase].self, forKey: .purchases) ?? []
        deferrals = try c.decodeIfPresent([Deferral].self, forKey: .deferrals) ?? []
    }
}

struct Suggestion: Identifiable {
    enum Tier: Equatable { case likely, maybe }

    var product: Product
    var quantity: Int
    var tier: Tier
    var progress: Double

    var id: UUID { product.id }
}

struct PredictionEvaluation: Identifiable {
    var product: Product
    var purchaseCount: Int
    var distinctTripCount: Int
    var intervalDays: Double?
    var daysSincePurchase: Double?
    var quantity: Int
    var progress: Double?
    var tier: Suggestion.Tier?
    var reason: String

    var id: UUID { product.id }

    var suggestion: Suggestion? {
        guard let tier, let progress else { return nil }
        return Suggestion(product: product, quantity: quantity, tier: tier, progress: progress)
    }
}
