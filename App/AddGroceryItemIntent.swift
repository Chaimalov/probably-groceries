import AppIntents
import Foundation

struct GroceryListEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "רשימת קניות"
    static var defaultQuery = GroceryListQuery()

    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ list: ShoppingList) {
        id = list.id
        name = list.name
    }
}

struct GroceryListQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GroceryListEntity] {
        let lists = ShoppingStore.shared.voiceWritableLists
        return identifiers.compactMap { id in lists.first { $0.id == id }.map(GroceryListEntity.init) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroceryListEntity] {
        GroceryCapture.lists(matching: string, in: ShoppingStore.shared.voiceWritableLists)
            .map(GroceryListEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [GroceryListEntity] {
        ShoppingStore.shared.voiceWritableLists.map(GroceryListEntity.init)
    }
}

struct AddGroceryItemIntent: AppIntent {
    static var title: LocalizedStringResource = "הוספת מוצר לקניות"
    static var description = IntentDescription("מוסיפה מוצר לרשימת קניות, גם כשהאפליקציה סגורה.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title: "מוצר", requestValueDialog: "מה להוסיף לקניות?")
    var item: String
    @Parameter(title: "רשימה")
    var list: GroceryListEntity?
    @Parameter(title: "כמות")
    var quantity: Int?
    @Parameter(title: "יחידת מידה")
    var unit: String?
    @Parameter(title: "מזהה בקשה (לאוטומציות)")
    var requestIdentifier: String?

    static var parameterSummary: some ParameterSummary {
        Summary("הוספת \(\.$item) לרשימה \(\.$list)") {
            \.$quantity
            \.$unit
            \.$requestIdentifier
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ShoppingStore.shared
        let lists = store.voiceWritableLists
        let preferred = UserDefaults.standard.string(forKey: GroceryCapture.defaultListKey)
            .flatMap(UUID.init(uuidString:))
        guard let destination = GroceryCapture.destination(explicit: list?.id, preferred: preferred, writable: lists) else {
            if list == nil, !lists.isEmpty {
                throw $list.needsValueError("לאיזו רשימת קניות להוסיף?")
            }
            throw CaptureFailure.listUnavailable
        }
        let requestID = requestIdentifier.flatMap(UUID.init(uuidString:))
        guard requestIdentifier == nil || requestID != nil else { throw CaptureFailure.invalidRequest }
        do {
            let capture = try store.captureGrocery(item, quantity: quantity, unit: unit,
                                                   listID: destination.id, requestID: requestID)
            return .result(dialog: "הוספתי את \(capture.item) לרשימה ״\(capture.list)״.")
        } catch ShoppingStore.CaptureError.invalidInput {
            throw CaptureFailure.invalidInput
        } catch ShoppingStore.CaptureError.listUnavailable {
            throw CaptureFailure.listUnavailable
        } catch {
            throw CaptureFailure.saveFailed
        }
    }
}

private enum CaptureFailure: LocalizedError {
    case listUnavailable, invalidInput, invalidRequest, saveFailed

    var errorDescription: String? {
        switch self {
        case .listUnavailable: String(localized: "הרשימה אינה זמינה לעריכה. בחרו רשימה אחרת או בדקו את השיתוף באפליקציה.")
        case .invalidInput: String(localized: "בדקו את שם המוצר, הכמות ויחידת המידה ונסו שוב.")
        case .invalidRequest: String(localized: "מזהה הבקשה צריך להיות UUID.")
        case .saveFailed: String(localized: "המוצר לא נשמר. פתחו את האפליקציה ונסו שוב.")
        }
    }
}

struct GroceryAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddGroceryItemIntent(),
            phrases: [
                "תוסיפי מוצר דרך \(.applicationName)",
                "תוסיפי מוצר לרשימה \(\.$list) דרך \(.applicationName)"
            ],
            shortTitle: "הוספת מוצר לקניות",
            systemImageName: "cart.badge.plus"
        )
    }
}
