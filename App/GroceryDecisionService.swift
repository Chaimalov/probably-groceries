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
    @Published private var outcomes: [UUID: Outcome] = [:]
    @Published private(set) var provider: GroceryDecisionProvider?
    private struct Connection: Codable {
        var provider: GroceryDecisionProvider; var key: String
        var listIDs: Set<UUID>; var sponsor: String
        var contractVersion: Int? = nil
    }
    private var connection: Connection?
    private var generation = UUID()
    private struct Outcome {
        var message: String
        var retryAt: Date = .distantPast
        var failures: Int = 0
    }

    private var task: Task<Void, Never>?
    private var activeListID: UUID?
    private weak var resumedStore: ShoppingStore?
    private var connecting = false
    private var lastRequestAt: [UUID: Date] = [:]
    private var providerRetryAt = Date.distantPast
    private let monitor = NWPathMonitor()
    private let defaults = UserDefaults.standard
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
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.online = path.status == .satisfied
                if !self.online { self.task?.cancel() }
                else if let store = self.resumedStore { self.schedule(store: store) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "groceries.intelligence.network"))
    }

    func sponsors(_ listID: UUID) -> Bool {
        connection?.contractVersion == GroceryDecisionContext.version && connection?.listIDs.contains(listID) == true
    }

    var sponsorName: String { connection?.sponsor ?? "" }

    private func digest(_ context: GroceryDecisionContext, includeSuppressions: Bool = true) -> String? {
        guard let bytes = try? context.revisionData(includeSuppressions: includeSuppressions) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func cachedBatch(in data: ShoppingData, listID: UUID, context: GroceryDecisionContext,
                     now: Date) -> GroceryDecisionBatch? {
        guard let batch = data.decisionBatches.first(where: { $0.listID == listID }),
              context.accepts(batch, listID: listID, historyRevision: digest(context, includeSuppressions: false),
                  provider: sponsors(listID) ? connection?.provider : nil, now: now) else { return nil }
        return batch
    }

    func status(for store: ShoppingStore, now: Date = .now) -> String {
        let listID = store.selectedListID
        if connecting { return "בודק חיבור…" }
        if busy && activeListID == listID { return "מכין המלצות…" }
        if let outcome = outcomes[listID], outcome.retryAt > now { return outcome.message }
        let context = GroceryDecisionContext(data: store.data, listID: listID, now: now)
        if let batch = cachedBatch(in: store.data, listID: listID, context: context, now: now) {
            if batch.recommendations.isEmpty { return "אין כרגע המלצות חדשות" }
            return context.suggestions(from: batch, in: store.data).isEmpty
                ? "כל ההמלצות כבר נוספו או נדחו" : "המלצות מהקניות האחרונות"
        }
        if !sponsors(listID) {
            if connection?.listIDs.contains(listID) == true { return "יש לאשר מחדש את החיבור בהגדרות" }
            return store.currentList.decisionRecommendations == true
                ? "ממתינים להמלצות ממכשיר שמחובר לספק" : "אפשר לחבר ספק המלצות בהגדרות"
        }
        if !online { return "אין חיבור לאינטרנט" }
        if context.state.products.isEmpty { return "עדיין אין היסטוריית קניות ברשימה" }
        if context.eligible.isEmpty { return "מוצרי ההיסטוריה כבר ברשימה או נדחו" }
        return "ממתינים לעדכון ההמלצות"
    }

    func diagnostic(for listID: UUID) -> String? {
        outcomes[listID]?.message
    }

    private func reserveRequest() throws {
        let day = Int(Date.now.timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "decisionRequestDay") != day {
            defaults.set(day, forKey: "decisionRequestDay"); defaults.set(0, forKey: "decisionRequestCount")
        }
        let count = defaults.integer(forKey: "decisionRequestCount")
        guard count < 20 else { throw GroceryDecisionError.quota }
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
        let listID = store.selectedListID
        guard online, store.canGenerateRecommendations(for: listID) else { throw GroceryDecisionError.unavailable }
        generation = UUID(); task?.cancel(); task = nil
        activeListID = nil
        let current = generation
        connecting = true
        busy = true
        defer {
            if generation == current { connecting = false; busy = false }
        }
        do {
            let now = Date.now
            let milk = Product(id: UUID(), name: "Synthetic example: milk", usualQuantity: 1)
            let purchase = Purchase(id: UUID(), productID: milk.id, quantity: 1,
                purchasedAt: now.addingTimeInterval(-7 * 86400), sourceItemID: UUID())
            let sample = GroceryDecisionContext(data: ShoppingData(products: [milk], purchases: [purchase]),
                listID: ShoppingList.defaultID, now: now)
            _ = try await GroceryDecisionClient(session: session).evaluate(provider: provider, key: key,
                context: sample, reserveRequest: reserveRequest)
            try Task.checkCancellation()
            guard generation == current, store.selectedListID == listID,
                  store.canGenerateRecommendations(for: listID) else { throw CancellationError() }
            let next = Connection(provider: provider, key: key, listIDs: [listID],
                sponsor: String(sponsor.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)), contractVersion: GroceryDecisionContext.version)
            let bytes = try JSONEncoder().encode(next)
            let attributes: [String: Any] = [kSecValueData as String: bytes,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let result = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
            let saved = result == errSecItemNotFound
                ? SecItemAdd(keychainQuery.merging(attributes) { _, new in new } as CFDictionary, nil) : result
            guard saved == errSecSuccess else { throw GroceryDecisionError.keyStorage }
            connection = next; self.provider = provider
            outcomes.removeAll()
            lastRequestAt.removeAll()
            providerRetryAt = .distantPast
            store.clearDecisionBatches(sponsorID: sponsorID)
            store.enableDecisionRecommendations()
        } catch {
            if generation == current { outcomes[listID] = Outcome(message: message(for: error)) }
            throw error
        }
    }

    func disconnect(store: ShoppingStore) throws {
        let result = SecItemDelete(keychainQuery as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw GroceryDecisionError.keyStorage }
        generation = UUID(); task?.cancel(); task = nil
        activeListID = nil
        connecting = false; busy = false
        connection = nil; provider = nil; outcomes.removeAll()
        store.clearDecisionBatches(sponsorID: sponsorID)
    }

    func schedule(store: ShoppingStore, force: Bool = false) {
        resumedStore = store
        let listID = store.selectedListID
        if let activeListID, activeListID != listID { task?.cancel() }
        guard let connection, sponsors(listID), store.currentList.decisionRecommendations == true,
              store.canGenerateRecommendations(for: listID), online, !connecting, task == nil,
              !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        let now = Date.now
        guard providerRetryAt <= now, (outcomes[listID]?.retryAt ?? .distantPast) <= now else { return }
        guard force || now.timeIntervalSince(lastRequestAt[listID] ?? .distantPast) >= 60 else { return }
        let context = GroceryDecisionContext(data: store.data, listID: listID, now: now)
        guard !context.eligible.isEmpty, let revision = digest(context),
              let historyRevision = digest(context, includeSuppressions: false) else { return }
        if !force, let cached = cachedBatch(in: store.data, listID: listID, context: context, now: now),
           (cached.revision == revision || now.timeIntervalSince(cached.generatedAt) < 15 * 60) { return }
        let current = generation
        activeListID = listID
        task = Task { [weak self, weak store] in
            guard let self else { return }
            defer {
                if self.generation == current {
                    self.task = nil
                    self.activeListID = nil
                    self.busy = false
                    if let store { self.schedule(store: store) }
                }
            }
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                guard let store, self.isCurrent(store, listID: listID, revision: revision) else { return }
                self.busy = true
                self.lastRequestAt[listID] = .now
                let ids = try await GroceryDecisionClient(session: self.session).evaluate(
                    provider: connection.provider, key: connection.key, context: context,
                    reserveRequest: self.reserveRequest)
                try Task.checkCancellation()
                guard self.generation == current, self.isCurrent(store, listID: listID, revision: revision) else { return }
                let saved = store.saveDecisionBatch(GroceryDecisionBatch(listID: listID, revision: revision,
                    generatedAt: .now, provider: connection.provider,
                    sponsor: connection.sponsor.isEmpty ? "שותף ברשימה" : connection.sponsor,
                    sponsorID: self.sponsorID, recommendations: ids, historyRevision: historyRevision))
                self.outcomes[listID] = saved
                    ? Outcome(message: ids.isEmpty ? "הספק לא הציע מוצרים הפעם" : "המלצות עודכנו")
                    : Outcome(message: "ההמלצות לא נשמרו במכשיר", retryAt: .now.addingTimeInterval(60))
            } catch is CancellationError { } catch {
                guard self.generation == current else { return }
                let failures = min(6, (self.outcomes[listID]?.failures ?? 0) + 1)
                let retry: TimeInterval
                switch error as? GroceryDecisionError {
                case .rateLimited(let delay):
                    retry = max(60, delay ?? 60 * pow(2, Double(failures)))
                    self.providerRetryAt = .now.addingTimeInterval(retry)
                case .quota: retry = 86400 - Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
                case .unauthorized, .rejectedRequest, .invalidResponse, .malformedResponse, .refused, .inputTooLarge:
                    retry = 3600
                default: retry = 60 * pow(2, Double(failures - 1))
                }
                self.outcomes[listID] = Outcome(message: self.message(for: error),
                    retryAt: .now.addingTimeInterval(retry), failures: failures)
            }
        }
    }

    private func isCurrent(_ store: ShoppingStore, listID: UUID, revision: String) -> Bool {
        guard online, store.selectedListID == listID, store.currentList.decisionRecommendations == true,
              store.canGenerateRecommendations(for: listID) else { return false }
        return digest(GroceryDecisionContext(data: store.data, listID: listID, now: .now)) == revision
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
