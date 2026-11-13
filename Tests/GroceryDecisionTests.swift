import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GroceryDecisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let listID = ShoppingList.defaultID

    // Synthetic, shaped like the diagnostic snapshot. Names, IDs, dates,
    // quantities and shopping patterns are generated independently.
    private func fixture(products count: Int = 1) -> ShoppingData {
        let products = (0..<count).map {
            Product(id: UUID(), name: "מוצר \($0)", usualQuantity: 1)
        }
        let purchases = (0..<(count + (count == 126 ? 98 : 0))).map { index in
            Purchase(id: UUID(), productID: products[index % count].id, quantity: 2,
                purchasedAt: now.addingTimeInterval(-Double(index % 62 + 1) * 86400), sourceItemID: UUID())
        }
        return ShoppingData(products: products, purchases: purchases)
    }

    private func context(_ data: ShoppingData) -> GroceryDecisionContext {
        GroceryDecisionContext(data: data, listID: listID, now: now)
    }

    func testSinglePurchasesReachBothProvidersAndJevBatchesAllChoices() async throws {
        let data = fixture(products: 126)
        let input = context(data)
        XCTAssertEqual(input.state.products.flatMap(\.events).count, 224)
        XCTAssertEqual(input.eligible.count, 126)
        for provider in GroceryDecisionProvider.allCases {
            var offered: Set<String> = []
            let result = try await evaluate(provider, input) { request in
                XCTAssertEqual(request.url, provider.endpoint)
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
                let body = try self.body(of: request)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let state = try XCTUnwrap(json[provider == .openAI ? "input" : "state"] as? String)
                XCTAssertFalse(state.contains(data.products[0].id.uuidString))
                let wire = try JSONDecoder().decode(GroceryDecisionContext.State.self, from: Data(state.utf8))
                XCTAssertEqual(wire.products, input.state.products)
                let questions = try self.questions(json, provider: provider)
                XCTAssertLessThanOrEqual(questions.count, provider.questionLimit)
                for (_, options) in questions {
                    XCTAssertLessThanOrEqual(options.count, provider.choiceLimit)
                    XCTAssertTrue(options.contains("none"))
                    offered.formUnion(options)
                }
                return try self.reply(provider, choices: questions.mapValues { _ in "none" })
            }
            XCTAssertEqual(offered, Set(input.eligible + ["none"]))
            XCTAssertEqual(result, [])
        }
    }

    func testMockModelOrderDrivesVisibleResultsAndLiveSuppression() async throws {
        var data = fixture(products: 3)
        let input = context(data)
        let ids = try await evaluate(.openAI, input) { request in
            let body = try self.body(of: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let questions = try self.questions(json, provider: .openAI)
            return try self.reply(.openAI, choices: questions.mapValues { $0.filter { $0 != "none" }.sorted().last! })
        }
        XCTAssertEqual(ids, Array(input.productIDs.reversed()))
        let batch = GroceryDecisionBatch(listID: listID, revision: "r", generatedAt: now,
            provider: .openAI, sponsor: "sample", sponsorID: "device", recommendations: ids)
        XCTAssertEqual(input.suggestions(from: batch, in: data).map(\.id), ids)
        XCTAssertEqual(input.suggestions(from: batch, in: data).map(\.quantity), [2, 2, 2])

        data.items = [ShoppingItem(id: UUID(), productID: ids[0], quantity: 1, addedAt: now)]
        data.deferrals = [Deferral(productID: ids[1], until: now.addingTimeInterval(3600))]
        let updated = context(data)
        XCTAssertEqual(updated.suggestions(from: batch, in: data).map(\.id), [ids[2]])
        XCTAssertEqual(updated.state.active.count, 1)
        XCTAssertEqual(updated.state.deferred.count, 1)
        XCTAssertEqual(updated.state.products.count, 3)
        XCTAssertNotEqual(try updated.revisionData(), try input.revisionData())
        XCTAssertEqual(try updated.revisionData(includeSuppressions: false), try input.revisionData(includeSuppressions: false))
    }

    func testJevFinalRoundComparesGroupWinners() async throws {
        let input = context(fixture(products: 25))
        let result = try await evaluate(.jev, input) { request in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try self.body(of: request)) as? [String: Any])
            let questions = try self.questions(json, provider: .jev)
            return try self.reply(.jev, choices: questions.mapValues { labels in
                if labels.contains("p23") { return "p23" }
                if labels.contains("p0") { return "p0" }
                return "none"
            })
        }
        XCTAssertEqual(result, [input.productIDs[23], input.productIDs[0]])
    }

    func testRevisionChangesOnPurchaseCorrectionButNotSyncArrivalOrder() throws {
        var data = fixture(products: 3)
        let first = try context(data).revisionData()
        data.purchases.reverse()
        data.products.reverse()
        XCTAssertEqual(first, try context(data).revisionData())
        data.purchases[0].quantity += 1
        XCTAssertNotEqual(first, try context(data).revisionData())
        for index in data.purchases.indices { data.purchases[index].listID = UUID() }
        XCTAssertTrue(context(data).state.products.isEmpty)
    }

    func testTransportAuthRateLimitMalformedAndInvalidResults() async throws {
        let input = context(fixture())
        let cases: [(Int, String, String)] = [
            (401, "private", "unauthorized"),
            (429, "private", "rateLimited"),
            (200, "{", "malformedResponse"),
            (200, #"{"model":"gpt-6-luna","answers":[]}"#, "invalidResponse"),
            (200, #"{"model":"gpt-6-luna","answers":[{"type":"refusal","name":"group0"}]}"#, "refused"),
            (200, #"{"model":"gpt-6-luna","answers":[{"type":"choice","name":"group0","choice":"p9"}]}"#, "invalidResponse"),
            (200, #"{"model":"gpt-6-luna","answers":[{"type":"choice","name":"group0","choice":"p0"},{"type":"choice","name":"group0","choice":"p0"}]}"#, "invalidResponse"),
        ]
        for (status, body, expected) in cases {
            do {
                _ = try await evaluate(.openAI, input) { _ in (status, Data(body.utf8)) }
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertTrue(String(describing: error).hasPrefix(expected), "\(error)")
                XCTAssertFalse(error.localizedDescription.contains("private"))
            }
        }
        do {
            _ = try await evaluate(.openAI, input) { _ in throw URLError(.notConnectedToInternet) }
            XCTFail("Expected a network error")
        } catch GroceryDecisionError.network {}
        XCTAssertEqual(GroceryDecisionClient.retryDelay("120", now: now), 120)
    }

    func testEmptyInputDoesNotReserveOrSendARequest() async throws {
        let result = try await evaluate(.openAI, context(ShoppingData()), reservations: { XCTFail("Reserved quota") }) { _ in
            XCTFail("Sent a request")
            return (500, Data())
        }
        XCTAssertTrue(result.isEmpty)
    }

    func testResultSyncRoutingAndTombstone() throws {
        var data = fixture()
        let batch = GroceryDecisionBatch(listID: listID, revision: "revision", generatedAt: now,
            provider: .jev, sponsor: "sample", sponsorID: "device", recommendations: [data.products[0].id],
            historyRevision: "history")
        data.decisionBatches = [batch]
        let key = "decision_\(listID.uuidString)"
        XCTAssertTrue(SharedListBinding.keys(in: data, listID: listID).contains(key))
        var journal = SyncJournal(); journal.seed(data, at: now)
        var receiver = ShoppingData(); var remoteJournal = SyncJournal()
        for revision in journal.revisions.values { _ = remoteJournal.merge(revision, into: &receiver) }
        XCTAssertEqual(receiver.decisionBatches, [batch])
        let before = data; data.decisionBatches = []
        journal.recordChanges(from: before, to: data, at: now.addingTimeInterval(1))
        XCTAssertTrue(remoteJournal.merge(try XCTUnwrap(journal.revisions[key]), into: &receiver))
        XCTAssertTrue(receiver.decisionBatches.isEmpty)
    }

    func testCacheRequiresMatchingEvidenceListProviderAndLifetime() {
        let input = context(fixture())
        var batch = GroceryDecisionBatch(listID: listID, revision: "request", generatedAt: now,
            provider: .openAI, sponsor: "sample", sponsorID: "device", recommendations: [],
            historyRevision: "history")
        XCTAssertTrue(input.accepts(batch, listID: listID, historyRevision: "history", provider: .openAI, now: now))
        XCTAssertTrue(input.accepts(batch, listID: listID, historyRevision: "history", provider: nil, now: now))
        XCTAssertFalse(input.accepts(batch, listID: UUID(), historyRevision: "history", provider: nil, now: now))
        XCTAssertFalse(input.accepts(batch, listID: listID, historyRevision: "history", provider: .jev, now: now))
        XCTAssertFalse(input.accepts(batch, listID: listID, historyRevision: "corrected", provider: nil, now: now))
        XCTAssertFalse(input.accepts(batch, listID: listID, historyRevision: "history", provider: nil,
            now: now.addingTimeInterval(GroceryDecisionContext.lifetime)))
        batch.historyRevision = nil
        XCTAssertFalse(input.accepts(batch, listID: listID, historyRevision: nil, provider: nil, now: now))
    }

    func testExistingActiveNameSuppressesHistoricalDuplicate() {
        var data = fixture()
        let name = data.products[0].name
        let alias = Product(id: UUID(), name: "  \(name)  ", usualQuantity: 1)
        data.products.append(alias)
        data.items.append(ShoppingItem(id: UUID(), productID: alias.id, quantity: 1, addedAt: now))
        let input = context(data)
        XCTAssertTrue(input.eligible.isEmpty)
        XCTAssertEqual(input.state.products.count, 1)
        XCTAssertEqual(input.state.activeWithoutHistory.count, 1)
    }

    func testOldStorageStillDecodes() throws {
        var data = fixture()
        data.decisionBatches = [GroceryDecisionBatch(listID: listID, revision: "old", generatedAt: now,
            provider: .jev, sponsor: "sample", sponsorID: "device", recommendations: [data.products[0].id])]
        let decoded = try JSONDecoder().decode(ShoppingData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.purchases, data.purchases)
        XCTAssertNil(decoded.decisionBatches.first?.historyRevision)
        XCTAssertTrue(try JSONDecoder().decode(ShoppingData.self, from: Data("{}".utf8)).decisionBatches.isEmpty)
    }

    @MainActor
    private func evaluate(_ provider: GroceryDecisionProvider, _ context: GroceryDecisionContext,
                          reservations: () throws -> Void = {},
                          mock: @escaping (URLRequest) throws -> (Int, Data)) async throws -> [UUID] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GroceryDecisionMockProtocol.self]
        let session = URLSession(configuration: configuration)
        GroceryDecisionMockProtocol.respond = mock
        defer { session.invalidateAndCancel(); GroceryDecisionMockProtocol.respond = nil }
        return try await GroceryDecisionClient(session: session).evaluate(provider: provider, key: "synthetic-key",
            context: context, reserveRequest: reservations)
    }

    private func body(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { return body }
            body.append(contentsOf: buffer.prefix(count))
        }
    }

    private func questions(_ json: [String: Any], provider: GroceryDecisionProvider) throws -> [String: [String]] {
        if provider == .openAI {
            let questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
            return try Dictionary(uniqueKeysWithValues: questions.map { question in
                let options = try XCTUnwrap(question["choices"] as? [[String: String]])
                return (try XCTUnwrap(question["name"] as? String), options.compactMap { $0["value"] })
            })
        }
        let questions = try XCTUnwrap(json["questions"] as? [String: [String: Any]])
        return try questions.mapValues { question in
            let criteria = try XCTUnwrap(question["criteria"] as? [String: String])
            return Array(criteria.keys)
        }
    }

    private func reply(_ provider: GroceryDecisionProvider, choices: [String: String]) throws -> (Int, Data) {
        let answers: Any = provider == .openAI
            ? choices.map { ["name": $0.key, "type": "choice", "choice": $0.value] }
            : choices.mapValues { ["type": "choice", "choice": $0] }
        return (200, try JSONSerialization.data(withJSONObject: ["model": provider.model, "answers": answers]))
    }
}

private final class GroceryDecisionMockProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, bytes) = try Self.respond!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
