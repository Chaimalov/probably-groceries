import Foundation

struct Product: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var usualQuantity: Int
}

struct ShoppingItem: Codable, Identifiable, Hashable {
    var id: UUID
    var productID: UUID
    var quantity: Int
    var addedAt: Date
}

struct Purchase: Codable, Identifiable, Hashable {
    var id: UUID
    var productID: UUID
    var quantity: Int
    var purchasedAt: Date
    var sourceItemID: UUID
}

struct Deferral: Codable, Hashable {
    var productID: UUID
    var until: Date
}

struct ShoppingData: Codable {
    var products: [Product] = []
    var items: [ShoppingItem] = []
    var purchases: [Purchase] = []
    var deferrals: [Deferral] = []
}

struct Suggestion: Identifiable {
    enum Tier { case likely, maybe }

    var product: Product
    var quantity: Int
    var tier: Tier
    var progress: Double

    var id: UUID { product.id }
}
