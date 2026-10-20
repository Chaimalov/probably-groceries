import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchShoppingStore: NSObject, ObservableObject, WCSessionDelegate {
    private struct Cache: Codable {
        var snapshot: WatchShoppingSnapshot?
        var pending: [WatchPurchaseCommand] = []
    }
    @Published private var cache = Cache()
    @Published private(set) var error: String?
    @Published private(set) var reachable = false
    private let file: URL
    var snapshot: WatchShoppingSnapshot? { cache.snapshot?.overlaying(cache.pending) }
    var pendingCount: Int { cache.pending.count }

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("watch-shopping.json")
        super.init()
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                cache = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: file))
            }
        } catch { self.error = String(localized: "לא ניתן לפתוח את הרשימה שנשמרה") }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func save(_ updated: Cache) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            cache = updated
            error = nil
            return true
        } catch {
            self.error = String(localized: "השינוי לא נשמר. נסו שוב.")
            return false
        }
    }

    @discardableResult
    func setPurchased(_ purchased: Bool, row: WatchShoppingSnapshot.Row, listID: UUID) -> Bool {
        var updated = cache
        updated.pending.append(WatchPurchaseCommand(id: UUID(), itemID: row.id,
            listID: listID, purchased: purchased, date: .now))
        guard save(updated) else { return false }
        refresh()
        return true
    }

    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        reachable = session.isReachable
        var message: [String: Any] = [WatchShoppingWire.refresh: true]
        if !cache.pending.isEmpty, let data = try? JSONEncoder().encode(cache.pending) {
            message[WatchShoppingWire.commands] = data
            // Every replacement contains the entire unacknowledged ordered queue.
            let queued = session.outstandingUserInfoTransfers
            if !queued.contains(where: {
                guard let bytes = $0.userInfo[WatchShoppingWire.commands] as? Data else { return false }
                return (try? JSONDecoder().decode([WatchPurchaseCommand].self, from: bytes)) == cache.pending
            }) {
                queued.forEach { $0.cancel() }
                session.transferUserInfo([WatchShoppingWire.commands: data])
            }
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { response in
                Task { @MainActor in self.receive(response) }
            }, errorHandler: { _ in
                Task { @MainActor in self.reachable = false }
            })
        }
    }

    private func receive(_ message: [String: Any]) {
        guard let data = message[WatchShoppingWire.snapshot] as? Data,
              let incoming = try? JSONDecoder().decode(WatchShoppingSnapshot.self, from: data),
              incoming.date >= (cache.snapshot?.date ?? .distantPast) else { return }
        var updated = cache
        updated.snapshot = incoming
        updated.pending.removeAll { incoming.receipts.contains($0.id) }
        if save(updated), updated.pending.isEmpty {
            WCSession.default.outstandingUserInfoTransfers.forEach { $0.cancel() }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                            error: Error?) {
        Task { @MainActor in
            self.receive(session.receivedApplicationContext)
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }
}
