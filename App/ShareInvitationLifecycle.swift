import CloudKit
import Combine
import UIKit
import UserNotifications

// SwiftUI's scene delegate receives both cold-launch and warm invitations.
// Queue them until the app's single store is ready, retaining failures for retry.
@MainActor
final class ShareInvitationInbox: ObservableObject {
    static let shared = ShareInvitationInbox()
    @Published private(set) var generation = 0
    private(set) var pending: [CKShare.Metadata] = []
    func enqueue(_ metadata: CKShare.Metadata) {
        guard !pending.contains(where: { $0.share.recordID == metadata.share.recordID }) else { return }
        pending.append(metadata)
        generation += 1
    }
    func removeFirst() { if !pending.isEmpty { pending.removeFirst() } }
    func retry() { generation += 1 }
}

final class SharingAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PhoneWatchBridge.shared.start()
        #if !targetEnvironment(simulator)
        application.registerForRemoteNotifications()
        ShoppingStore.shared.cloudSync.start()
        #endif
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.containerIdentifier == PersonalCloudSync.containerIdentifier else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let store = ShoppingStore.shared
            await store.cloudSync.synchronize()
            completionHandler(store.syncStatus == .current ? .newData : .failed)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard info["groceriesAction"] as? String == "clarification",
              let item = (info["itemID"] as? String).flatMap(UUID.init(uuidString:)),
              let list = (info["listID"] as? String).flatMap(UUID.init(uuidString:)) else {
            completionHandler(); return
        }
        Task { @MainActor in
            ShoppingStore.shared.widgetNavigation = ShoppingStore.WidgetNavigation(
                itemID: item, listID: list, openClarification: true)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SharingSceneDelegate.self
        return configuration
    }
}

final class SharingSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { ShareInvitationInbox.shared.enqueue(metadata) }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInvitationInbox.shared.enqueue(cloudKitShareMetadata)
    }
}
