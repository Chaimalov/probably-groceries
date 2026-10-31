import Foundation
import Combine
import CryptoKit
import Security
import Network

@MainActor
final class GroceryDecisionService: ObservableObject {
    static let shared = GroceryDecisionService()
    @Published private(set) var online = false
    @Published private(set) var busy = false
    @Published private(set) var status = "לא מחובר"
    @Published private(set) var provider: GroceryDecisionProvider?
    private struct Connection: Codable {
        var provider: GroceryDecisionProvider; var key: String
        var listIDs: Set<UUID>; var sponsor: String
    }
    private var connection: Connection?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private let defaults = UserDefaults.standard
    private var retryAfter = Date.distantPast
    private var lastRequests: [UUID: Date] = [:]
    private let sponsorID: String
    private let redirectGuard = GroceryDecisionRedirectGuard()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        config.urlCache = nil
        return URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }()
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.chaimalov.probablygroceries.intelligence",
         kSecAttrAccount as String: "provider"]
    }

    private init() {
        let id = defaults.string(forKey: "decisionSponsorID") ?? UUID().uuidString
        sponsorID = id; defaults.set(id, forKey: "decisionSponsorID")
        var query = keychainQuery; query[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let bytes = item as? Data {
            connection = try? JSONDecoder().decode(Connection.self, from: bytes)
        }
        provider = connection?.provider
        status = provider == nil ? "לא מחובר" : "מחובר"
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.online = path.status == .satisfied
                if !self.online { self.task?.cancel() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "groceries.intelligence.network"))
    }

    func sponsors(_ listID: UUID) -> Bool { connection?.listIDs.contains(listID) == true }
    var sponsorName: String { connection?.sponsor ?? "" }
    func revision(_ data: ShoppingData, listID: UUID, now: Date = .now) -> String? {
        guard let bytes = try? GroceryDecisionContract.revisionData(data, listID: listID, now: now) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func reserveRequest() throws {
        let day = Int(Date.now.timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "decisionRequestDay") != day {
            defaults.set(day, forKey: "decisionRequestDay"); defaults.set(0, forKey: "decisionRequestCount")
        }
        let count = defaults.integer(forKey: "decisionRequestCount")
        guard count < 20, retryAfter <= .now else { throw GroceryDecisionError.quota }
        // Includes failures and synthetic tests. Never persist the API key here.
        defaults.set(count + 1, forKey: "decisionRequestCount")
    }

    func connect(provider: GroceryDecisionProvider, key text: String, sponsor: String,
                 store: ShoppingStore) async throws {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 512, !key.contains(where: { $0.isWhitespace || $0.isNewline }),
              key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            throw GroceryDecisionError.invalidKey
        }
        guard online else { throw GroceryDecisionError.unavailable }
        generation = UUID(); task?.cancel(); task = nil
        let current = generation; busy = true; status = "בודק חיבור…"
        defer { if generation == current { busy = false } }
        do {
            try reserveRequest()
            let sample = GroceryDecisionCandidate(id: UUID(), name: "Synthetic example: milk", unit: nil,
                quantity: 1, events: [.init(daysAgo: 21, quantity: 1), .init(daysAgo: 14, quantity: 1), .init(daysAgo: 7, quantity: 1)])
            _ = try await GroceryDecisionClient(session: session).evaluate(provider: provider, key: key, candidates: [sample])
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let lists: Set<UUID> = [store.selectedListID]
            let next = Connection(provider: provider, key: key, listIDs: lists,
                sponsor: String(sponsor.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)))
            let bytes = try JSONEncoder().encode(next)
            let attributes: [String: Any] = [kSecValueData as String: bytes,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let result = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
            let saved = result == errSecItemNotFound
                ? SecItemAdd(keychainQuery.merging(attributes) { _, new in new } as CFDictionary, nil) : result
            guard saved == errSecSuccess else { throw GroceryDecisionError.keyStorage }
            connection = next; self.provider = provider; status = "מחובר"
            lastRequests.removeAll(); retryAfter = .distantPast
            store.clearDecisionBatches(sponsorID: sponsorID)
            store.enableDecisionRecommendations()
        } catch {
            if generation == current { status = message(for: error) }
            throw error
        }
    }

    func disconnect(store: ShoppingStore) throws {
        let result = SecItemDelete(keychainQuery as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw GroceryDecisionError.keyStorage }
        generation = UUID(); task?.cancel(); task = nil; busy = false
        connection = nil; provider = nil; status = "לא מחובר"
        store.clearDecisionBatches(sponsorID: sponsorID)
    }

    func schedule(store: ShoppingStore, force: Bool = false) {
        let listID = store.selectedListID
        guard let connection, connection.listIDs.contains(listID),
              store.currentList.decisionRecommendations == true, online, !busy,
              retryAfter <= .now, task == nil,
              !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        let data = store.data
        guard let revision = revision(data, listID: listID) else { return }
        let fresh = data.decisionBatches.first { $0.listID == listID && $0.revision == revision &&
            $0.generatedAt <= .now && Date.now.timeIntervalSince($0.generatedAt) < GroceryDecisionContract.lifetime }
        guard force || fresh == nil else { return }
        guard force || Date.now.timeIntervalSince(lastRequests[listID] ?? .distantPast) >= 15 * 60 else { return }
        let current = generation
        task = Task { [weak self, weak store] in
            guard let self else { return }
            defer { if self.generation == current { self.task = nil; self.busy = false } }
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                guard let store, store.selectedListID == listID,
                      self.revision(store.data, listID: listID) == revision else { return }
                self.busy = true; self.status = "מכין המלצות…"
                let candidates = GroceryDecisionContract.candidates(in: data, listID: listID, now: .now)
                let ids: [UUID]
                if candidates.isEmpty { ids = [] } else {
                    try self.reserveRequest(); self.lastRequests[listID] = .now
                    ids = try await GroceryDecisionClient(session: self.session).evaluate(
                        provider: connection.provider, key: connection.key, candidates: candidates)
                }
                try Task.checkCancellation()
                guard self.generation == current, self.online,
                      store.data.lists.contains(where: { $0.id == listID && $0.decisionRecommendations == true }),
                      self.revision(store.data, listID: listID) == revision else { return }
                store.saveDecisionBatch(GroceryDecisionBatch(listID: listID, revision: revision,
                    generatedAt: .now, provider: connection.provider,
                    sponsor: connection.sponsor.isEmpty ? "שותף ברשימה" : connection.sponsor,
                    sponsorID: self.sponsorID, recommendations: ids))
                self.status = candidates.isEmpty ? "עדיין אין מספיק קניות חוזרות" : "ההמלצות עודכנו"
            } catch is CancellationError { } catch {
                guard self.generation == current else { return }
                self.status = self.message(for: error)
                self.retryAfter = Date.now.addingTimeInterval(3600)
            }
        }
    }

    private func message(for error: Error) -> String {
        (error as? GroceryDecisionError)?.errorDescription ?? "לא הצלחנו להגיע לספק. אפשר לנסות שוב מאוחר יותר."
    }
}

private final class GroceryDecisionRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
