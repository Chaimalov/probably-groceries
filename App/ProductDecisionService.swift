import Foundation
import Combine
import CryptoKit
import Security

@MainActor
final class ProductDecisionService: ObservableObject {
    static let shared = ProductDecisionService()
    @Published private(set) var status = "לא מחובר"
    @Published private(set) var connected = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var retryAfter = Date.distantPast
    private let defaults = UserDefaults.standard
    private let keychainService = "com.chaimalov.probablygroceries.decisions"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoDecisionRedirects(), delegateQueue: nil)
    }()

    struct Credentials: Codable { let endpoint: URL; let token: String; let deviceID: String }
    struct WireProduct: Codable { let id: UUID; let name: String; let unit: String? }
    struct MatchRequest: Codable { let source: WireProduct; let candidates: [WireProduct] }
    struct Decision: Codable {
        let sourceID: UUID
        let targetID: UUID?
        let decision: String
        let probability: Double
        let confidence: Double
        let model: String
        let policyVersion: String
        let learningEnabled: Bool
    }
    struct Cached: Codable { let decision: Decision; let expiresAt: Date }
    private var cache: [String: Cached] = [:]

    private init() {
        connected = credentials() != nil
        status = connected ? "מחובר" : "לא מחובר"
        if let bytes = defaults.data(forKey: "productDecisionCache") {
            cache = (try? JSONDecoder().decode([String: Cached].self, from: bytes)) ?? [:]
        }
        cache = cache.filter { $0.value.expiresAt > .now }
    }

    var endpoint: String { credentials()?.endpoint.absoluteString ?? "" }
    var deviceID: String { credentials()?.deviceID ?? "" }

    func connect(endpoint text: String, code: String, store: ShoppingStore) async throws {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw ServiceError.message("כתובת השרת צריכה להתחיל ב־https:// וללא נתיב נוסף.")
        }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 64, code.allSatisfy({ $0.isHexDigit }) else {
            throw ServiceError.message("קוד החיבור אינו תקין.")
        }
        let current = generation
        let bytes = try await request(url.appendingPathComponent("v1/enroll"), token: nil,
            body: JSONEncoder().encode(["code": code.lowercased()]))
        struct Enrollment: Decodable { let token: String; let deviceID: String }
        let enrollment = try JSONDecoder().decode(Enrollment.self, from: bytes)
        guard enrollment.token.count == 64, enrollment.deviceID.count == 64 else { throw ServiceError.invalidResponse }
        guard generation == current else { throw CancellationError() }
        let credentials = Credentials(endpoint: url, token: enrollment.token, deviceID: enrollment.deviceID)
        let data = try JSONEncoder().encode(credentials)
        let query = keychainQuery()
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        let saved = result == errSecItemNotFound
            ? SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) : result
        guard saved == errSecSuccess else { throw ServiceError.message("לא הצלחנו לשמור את החיבור במכשיר.") }
        generation = UUID()
        task?.cancel(); task = nil
        connected = true; status = "מחובר"; retryAfter = .distantPast
        schedule(store: store)
    }

    func disconnect() {
        generation = UUID(); task?.cancel(); task = nil
        SecItemDelete(keychainQuery() as CFDictionary)
        connected = false; status = "לא מחובר"
        cache.removeAll(); defaults.removeObject(forKey: "productDecisionCache")
    }

    func schedule(store: ShoppingStore) {
        guard task == nil, connected, retryAfter <= .now,
              !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        let current = generation
        task = Task { [weak self, weak store] in
            defer { if self?.generation == current { self?.task = nil } }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, let store, let credentials = self.credentials(), self.generation == current else { return }
            await self.process(store: store, credentials: credentials, generation: current)
        }
    }

    private func process(store: ShoppingStore, credentials: Credentials, generation current: UUID) async {
        var calls = 0
        let listIDs = store.data.lists.map(\.id)
        for listID in listIDs {
            let ids = Set(store.data.items.filter { $0.listID == listID }.map(\.productID)
                + store.data.purchases.filter { $0.listID == listID }.map(\.productID))
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard generation == current, !Task.isCancelled, calls < 20, store.storageError == nil else { return }
                guard let source = store.product(for: id) else { continue }
                let candidates = ProductLearning.candidates(for: source, in: store.data, listID: listID)
                guard !candidates.isEmpty else { continue }
                let payload = MatchRequest(source: wire(source), candidates: candidates.map(wire))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                guard let body = try? encoder.encode(payload) else { continue }
                let key = SHA256.hash(data: Data((credentials.endpoint.absoluteString + listID.uuidString + "product-identity-v1").utf8) + body)
                    .map { String(format: "%02x", $0) }.joined()
                let decision: Decision
                do {
                    if let saved = cache[key], saved.expiresAt > .now { decision = saved.decision }
                    else {
                        calls += 1; status = "מזהה שמות מוצרים ברקע"
                        let bytes = try await request(credentials.endpoint.appendingPathComponent("v1/match"), token: credentials.token, body: body)
                        decision = try JSONDecoder().decode(Decision.self, from: bytes)
                        guard decision.sourceID == source.id, decision.policyVersion == "product-identity-v1",
                              decision.probability.isFinite, (0...1).contains(decision.probability),
                              decision.confidence.isFinite, (0...1).contains(decision.confidence),
                              ["same", "different", "uncertain"].contains(decision.decision),
                              decision.targetID == nil || candidates.contains(where: { $0.id == decision.targetID }) else {
                            throw ServiceError.invalidResponse
                        }
                        guard generation == current, !Task.isCancelled else { return }
                        cache[key] = Cached(decision: decision, expiresAt: .now.addingTimeInterval(decision.learningEnabled ? 7 * 86400 : 3600))
                        cache = cache.filter { $0.value.expiresAt > .now }
                        defaults.set(try JSONEncoder().encode(cache), forKey: "productDecisionCache")
                    }
                    guard generation == current, !Task.isCancelled else { return }
                    if decision.learningEnabled, decision.decision == "same", decision.probability >= 0.98,
                       decision.confidence >= 0.9, let target = candidates.first(where: { $0.id == decision.targetID }) {
                        store.recordLearningLink(from: source, to: target, listID: listID, decision: decision)
                    }
                    status = decision.learningEnabled ? "מחובר" : "מחובר · בדיקת דיוק"
                } catch {
                    guard generation == current, !Task.isCancelled else { return }
                    if case ServiceError.unauthorized = error { status = "נדרש חיבור מחדש"; connected = false }
                    else { status = "ננסה שוב בהמשך"; retryAfter = .now.addingTimeInterval(3600) }
                    return
                }
            }
        }
    }

    private func wire(_ product: Product) -> WireProduct { WireProduct(id: product.id, name: product.name, unit: product.preferredUnit) }
    private func request(_ url: URL, token: String?, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        if http.statusCode == 401 { throw ServiceError.unauthorized }
        guard (200...299).contains(http.statusCode), data.count < 32768 else { throw ServiceError.invalidResponse }
        return data
    }
    private func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "device", kSecAttrSynchronizable as String: false]
    }
    private func credentials() -> Credentials? {
        var query = keychainQuery(); query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let bytes = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: bytes)
    }
    enum ServiceError: LocalizedError {
        case unauthorized, invalidResponse, message(String)
        var errorDescription: String? {
            switch self {
            case .unauthorized: return "קוד החיבור פג או שהגישה בוטלה. נסו קוד חדש."
            case .invalidResponse: return "השירות לא זמין כרגע. נסו שוב בהמשך."
            case .message(let message): return message
            }
        }
    }
}

private final class NoDecisionRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
