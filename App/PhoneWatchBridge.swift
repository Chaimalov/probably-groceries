import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    private var latest: WatchShoppingSnapshot?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ snapshot: WatchShoppingSnapshot) {
        latest = snapshot
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext([WatchShoppingWire.snapshot: data])
    }

    private func receive(_ message: [String: Any]) -> [String: Any] {
        let store = ShoppingStore.shared
        let commands = (message[WatchShoppingWire.commands] as? Data)
            .flatMap { try? JSONDecoder().decode([WatchPurchaseCommand].self, from: $0) } ?? []
        if !commands.isEmpty { store.applyWatchCommands(commands) }
        let snapshot = store.watchSnapshot(acknowledging: commands)
        guard store.storageError == nil,
              let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        publish(snapshot)
        return [WatchShoppingWire.snapshot: data]
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                            error: Error?) {
        Task { @MainActor in
            if let latest = self.latest { self.publish(latest) }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            if let latest = self.latest { self.publish(latest) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                            replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.receive(message)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in _ = self.receive(userInfo) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
