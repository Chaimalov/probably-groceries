import Foundation

struct Product: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var usualQuantity: Int
    var category: String? = nil
    var department: String? = nil
    var preferredUnit: String? = nil
    var learningLinks: [ProductLearningLink]? = nil
}

struct ShoppingList: Codable, Identifiable, Hashable {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var id: UUID
    var name: String
    var sections: [String] = []
    var tintName: String = "green"
    var symbolName: String = "cart"
    var sectionStyles: [String: SectionAppearance]? = nil
    var sectionAliases: [String: String]? = nil
    var decisionRecommendations: Bool? = nil

    enum CodingKeys: String, CodingKey { case id, name, sections, tintName, symbolName, sectionStyles, sectionAliases, decisionRecommendations }
    init(id: UUID, name: String, sections: [String] = [], tintName: String = "green", symbolName: String = "cart") {
        self.id = id; self.name = name; self.sections = sections
        self.tintName = tintName; self.symbolName = symbolName
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sections = try c.decodeIfPresent([String].self, forKey: .sections) ?? []
        tintName = try c.decodeIfPresent(String.self, forKey: .tintName) ?? "green"
        symbolName = try c.decodeIfPresent(String.self, forKey: .symbolName) ?? "cart"
        sectionStyles = try c.decodeIfPresent([String: SectionAppearance].self, forKey: .sectionStyles)
        sectionAliases = try c.decodeIfPresent([String: String].self, forKey: .sectionAliases)
        decisionRecommendations = try c.decodeIfPresent(Bool.self, forKey: .decisionRecommendations)
    }
}

struct ShoppingItem: Codable, Identifiable, Hashable {
    var id: UUID
    var productID: UUID
    var quantity: Int
    var addedAt: Date
    var listID: UUID = ShoppingList.defaultID
    var isUrgent: Bool = false
    var manualOrder: Int? = nil
    var note: String? = nil
    var photoFilename: String? = nil
    var unit: String? = nil
    var sectionName: String? = nil
    var shoppingPlace: String? = nil
    var photoData: Data? = nil
    var clarification: ItemClarification? = nil
    var unavailable: Bool? = nil

    enum CodingKeys: String, CodingKey { case id, productID, quantity, addedAt, listID, isUrgent, manualOrder, note, photoFilename, unit, sectionName, shoppingPlace, photoData, clarification, unavailable }
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
        manualOrder = try c.decodeIfPresent(Int.self, forKey: .manualOrder)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        sectionName = try c.decodeIfPresent(String.self, forKey: .sectionName)
        shoppingPlace = try c.decodeIfPresent(String.self, forKey: .shoppingPlace)
        photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)
        clarification = try c.decodeIfPresent(ItemClarification.self, forKey: .clarification)
        unavailable = try c.decodeIfPresent(Bool.self, forKey: .unavailable)
    }
}

struct Purchase: Codable, Identifiable, Hashable {
    var id: UUID
    var productID: UUID
    var quantity: Int
    var purchasedAt: Date
    var sourceItemID: UUID
    var listID: UUID = ShoppingList.defaultID
    var actorID: String? = nil
    var originalOrder: Int? = nil
    var wasUrgent: Bool = false
    var note: String? = nil
    var photoFilename: String? = nil
    var unit: String? = nil
    var sectionName: String? = nil
    var shoppingPlace: String? = nil
    var photoData: Data? = nil
    var clarification: ItemClarification? = nil
    var unavailable: Bool? = nil

    enum CodingKeys: String, CodingKey { case id, productID, quantity, purchasedAt, sourceItemID, listID, actorID, originalOrder, wasUrgent, note, photoFilename, unit, sectionName, shoppingPlace, photoData, clarification, unavailable }
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
        actorID = try c.decodeIfPresent(String.self, forKey: .actorID)
        originalOrder = try c.decodeIfPresent(Int.self, forKey: .originalOrder)
        wasUrgent = try c.decodeIfPresent(Bool.self, forKey: .wasUrgent) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
        photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        sectionName = try c.decodeIfPresent(String.self, forKey: .sectionName)
        shoppingPlace = try c.decodeIfPresent(String.self, forKey: .shoppingPlace)
        photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)
        clarification = try c.decodeIfPresent(ItemClarification.self, forKey: .clarification)
        unavailable = try c.decodeIfPresent(Bool.self, forKey: .unavailable)
    }
}

struct Deferral: Codable, Hashable {
    var productID: UUID
    var until: Date
    var recordedAt: Date? = nil
    var listID: UUID = ShoppingList.defaultID

    enum CodingKeys: String, CodingKey { case productID, until, listID, recordedAt }
    init(productID: UUID, until: Date, listID: UUID = ShoppingList.defaultID) {
        self.productID = productID; self.until = until; self.listID = listID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        productID = try c.decode(UUID.self, forKey: .productID)
        until = try c.decode(Date.self, forKey: .until)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt)
        listID = try c.decodeIfPresent(UUID.self, forKey: .listID) ?? ShoppingList.defaultID
    }
}

struct ShoppingData: Codable {
    var lists: [ShoppingList] = [ShoppingList(id: ShoppingList.defaultID, name: "קניות")]
    var products: [Product] = []
    var items: [ShoppingItem] = []
    var purchases: [Purchase] = []
    var deferrals: [Deferral] = []
    // Device-local receipts, persisted atomically with confirmed additions.
    var confirmedDrafts: [UUID] = []

    var watchReceipts: [UUID] = []
    var decisionBatches: [GroceryDecisionBatch] = []

    enum CodingKeys: String, CodingKey { case lists, products, items, purchases, deferrals, confirmedDrafts, watchReceipts, decisionBatches }
    init(lists: [ShoppingList] = [ShoppingList(id: ShoppingList.defaultID, name: "קניות")],
         products: [Product] = [], items: [ShoppingItem] = [],
         purchases: [Purchase] = [], deferrals: [Deferral] = []) {
        self.lists = lists; self.products = products; self.items = items
        self.purchases = purchases; self.deferrals = deferrals
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lists = try c.decodeIfPresent([ShoppingList].self, forKey: .lists)
            ?? [ShoppingList(id: ShoppingList.defaultID, name: "קניות")]
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        items = try c.decodeIfPresent([ShoppingItem].self, forKey: .items) ?? []
        purchases = try c.decodeIfPresent([Purchase].self, forKey: .purchases) ?? []
        deferrals = try c.decodeIfPresent([Deferral].self, forKey: .deferrals) ?? []
        confirmedDrafts = try c.decodeIfPresent([UUID].self, forKey: .confirmedDrafts) ?? []
        watchReceipts = try c.decodeIfPresent([UUID].self, forKey: .watchReceipts) ?? []
        decisionBatches = try c.decodeIfPresent([GroceryDecisionBatch].self, forKey: .decisionBatches) ?? []
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




struct SectionAppearance: Codable, Hashable {
    var symbol: String
    var tint: String
}

struct ItemClarification: Codable, Hashable {
    var question: String
    var answer: String? = nil
    var resolved: Bool = false
}
