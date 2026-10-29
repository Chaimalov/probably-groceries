import Foundation
import UserNotifications

@MainActor
final class ShoppingBadge {
    static let shared = ShoppingBadge()
    private var updateTask: Task<Void, Never>?
    private var generation = 0

    // Coalesce updates and serialize submissions so an older count cannot finish last.
    func update(data: ShoppingData, selectedListID: UUID) {
        generation += 1
        let revision = generation
        let previous = updateTask
        let count = BadgePolicy.count(in: data, selectedListID: selectedListID)
        updateTask = Task {
            await previous?.value
            guard revision == generation else { return }
            do { try await UNUserNotificationCenter.current().setBadgeCount(count) }
            catch { /* Settings exposes disabled permissions; retry at the next update. */ }
        }
    }
}
