import Foundation

/// A replayable snapshot of prediction inputs. No photos, notes or account metadata.
struct PredictionDiagnostics: Encodable {
    struct Evaluation: Encodable {
        let productID: UUID
        let purchaseCount: Int
        let distinctTripCount: Int
        let intervalDays: Double?
        let daysSincePurchase: Double?
        let suggestedQuantity: Int
        let progress: Double?
        let tier: String?
        let reason: String

        init(_ value: PredictionEvaluation) {
            productID = value.id
            purchaseCount = value.purchaseCount
            distinctTripCount = value.distinctTripCount
            intervalDays = value.intervalDays
            daysSincePurchase = value.daysSincePurchase
            suggestedQuantity = value.quantity
            progress = value.progress
            tier = value.tier.map { $0 == .likely ? "likely" : "maybe" }
            reason = value.reason
        }
    }

    struct ListEvaluation: Encodable {
        let listID: UUID
        let products: [Evaluation]
    }

    struct DraftSummary: Encodable {
        struct Entry: Encodable {
            let productID: UUID?
            let name: String
            let quantity: Int
            let unit: String?
            let included: Bool
        }
        let listID: UUID
        let createdAt: Date
        let alreadyConfirmed: Bool
        let entries: [Entry]
    }

    let schemaVersion = 1
    let generatedAt: Date
    let timeZoneIdentifier: String
    let appVersion: String
    let buildNumber: String
    let selectedListID: UUID
    let storageError: String?
    let shoppingData: ShoppingData
    let evaluations: [ListEvaluation]
    let cachedDrafts: [DraftSummary]

    init(data: ShoppingData, selectedListID: UUID, drafts: [ShoppingDraft] = [],
         now: Date = .now, appVersion: String = "", buildNumber: String = "",
         storageError: String? = nil) {
        generatedAt = now
        timeZoneIdentifier = TimeZone.current.identifier
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.selectedListID = selectedListID
        self.storageError = storageError
        // Copy only fields useful for reproducing timing, quantities and exclusions.
        shoppingData = ShoppingData(lists: data.lists, products: data.products,
            items: data.items.map { value in
                var item = ShoppingItem(id: value.id, productID: value.productID,
                    quantity: value.quantity, addedAt: value.addedAt,
                    listID: value.listID, isUrgent: value.isUrgent)
                item.unit = value.unit
                item.sectionName = value.sectionName
                item.manualOrder = value.manualOrder
                return item
            }, purchases: data.purchases.map { value in
                var purchase = Purchase(id: value.id, productID: value.productID,
                    quantity: value.quantity, purchasedAt: value.purchasedAt,
                    sourceItemID: value.sourceItemID, listID: value.listID, wasUrgent: value.wasUrgent)
                purchase.unit = value.unit
                purchase.sectionName = value.sectionName
                purchase.originalOrder = value.originalOrder
                return purchase
            }, deferrals: data.deferrals)
        evaluations = data.lists.map { list in
            ListEvaluation(listID: list.id,
                products: PredictionEngine.evaluate(data, now: now, listID: list.id).map(Evaluation.init))
        }
        cachedDrafts = drafts.map { draft in
            DraftSummary(listID: draft.listID, createdAt: draft.createdAt,
                alreadyConfirmed: data.confirmedDrafts.contains(draft.token),
                entries: draft.entries.map {
                    DraftSummary.Entry(productID: $0.productID, name: $0.name,
                        quantity: $0.quantity, unit: $0.unit, included: $0.included)
                })
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
