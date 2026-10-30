import Foundation
import UserNotifications

@MainActor
enum ClarificationNotifications {
    static let preference = "clarificationNotificationsEnabled"
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: preference) == nil || UserDefaults.standard.bool(forKey: preference)
    }

    static func requestPermission(hasSharedLists: Bool) async {
        #if !targetEnvironment(simulator)
        guard enabled, hasSharedLists else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        #endif
    }

    static func enqueue(_ notices: [ClarificationNotice], products: [Product], items: [ShoppingItem]) {
        #if !targetEnvironment(simulator)
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        for notice in notices {
            guard let item = items.first(where: { $0.id == notice.itemID }),
                  let product = products.first(where: { $0.id == item.productID }) else { continue }
            let content = UNMutableNotificationContent()
            let format = notice.kind == .question ? NSLocalizedString("שאלה על %@", comment: "Product question")
                : NSLocalizedString("יש תשובה לגבי %@", comment: "Product answer")
            content.title = String(format: format, product.name)
            content.body = String(notice.text.prefix(160))
            content.sound = .default
            content.categoryIdentifier = "product-clarification"
            content.threadIdentifier = notice.listID.uuidString
            content.userInfo = ["groceriesAction": "clarification", "itemID": notice.itemID.uuidString,
                                "listID": notice.listID.uuidString]
            // Identical merged revisions never enqueue a second notice.
            center.add(UNNotificationRequest(identifier: "clarification-" + notice.itemID.uuidString,
                                             content: content, trigger: nil), withCompletionHandler: { _ in })
        }
        #endif
    }
}
