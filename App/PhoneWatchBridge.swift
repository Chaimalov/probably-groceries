import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    private var latest: WatchShoppingSnapshot?

    func start() {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ snapshot: WatchShoppingSnapshot) {
        latest = snapshot
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let payload: [String: Any] = [WatchShoppingWire.snapshot: data]
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                // The application context remains queued if live delivery fails.
            })
        }
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

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable, let latest = self.latest { self.publish(latest) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                            replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            // Reply promptly with durable local state; push fresh cloud state
            // as it arrives rather than timing out WatchConnectivity's reply.
            replyHandler(self.receive(message))
            if message[WatchShoppingWire.refresh] as? Bool == true {
                await ShoppingStore.shared.cloudSync.synchronize()
                self.publish(ShoppingStore.shared.watchSnapshot())
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            _ = self.receive(userInfo)
            await ShoppingStore.shared.cloudSync.synchronize()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
