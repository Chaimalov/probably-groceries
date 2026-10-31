import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GroceryDecisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() -> ShoppingData {
        let product = Product(id: UUID(), name: "חלב", usualQuantity: 1)
        let purchases = [21, 14, 7].map { days in
            Purchase(id: UUID(), productID: product.id, quantity: 2,
                purchasedAt: now.addingTimeInterval(Double(-days) * 86400), sourceItemID: UUID())
        }
        return ShoppingData(products: [product], purchases: purchases)
    }
    private func candidates(_ data: ShoppingData) -> [GroceryDecisionCandidate] {
        GroceryDecisionContract.candidates(in: data, listID: ShoppingList.defaultID, now: now)
    }

    func testCandidatesDoNotUseLocalPredictionThreshold() {
        var data = fixture()
        // Weekly purchases yesterday: local predictor says too early, decision model still gets evidence.
        data.purchases = data.purchases.map { var p = $0; p.purchasedAt.addTimeInterval(6 * 86400); return p }
        XCTAssertNil(PredictionEngine.evaluate(data, now: now).first?.tier)
        XCTAssertEqual(candidates(data).count, 1)
        XCTAssertEqual(candidates(data).first?.quantity, 2)
    }
    func testActiveDeferralAndInsufficientHistoryAreSuppressed() {
        var data = fixture()
        let id = data.products[0].id
        data.items = [ShoppingItem(id: UUID(), productID: id, quantity: 1, addedAt: now)]
        XCTAssertTrue(candidates(data).isEmpty)
        data.items = []
        data.deferrals = [Deferral(productID: id, until: now.addingTimeInterval(3600))]
        XCTAssertTrue(candidates(data).isEmpty)
        data.deferrals = []; data.purchases.removeLast()
        XCTAssertTrue(candidates(data).isEmpty)
    }
    func testOtherListsDoNotProvideEvidence() {
        var data = fixture()
        for index in data.purchases.indices { data.purchases[index].listID = UUID() }
        XCTAssertTrue(candidates(data).isEmpty)
    }
    func testRevisionStableAcrossSyncArrivalOrderAndChangesOnUndo() throws {
        var data = fixture()
        let first = try GroceryDecisionContract.revisionData(data, listID: ShoppingList.defaultID, now: now)
        data.purchases.reverse()
        XCTAssertEqual(first, try GroceryDecisionContract.revisionData(data, listID: ShoppingList.defaultID, now: now))
        data.purchases.removeLast()
        XCTAssertNotEqual(first, try GroceryDecisionContract.revisionData(data, listID: ShoppingList.defaultID, now: now))
    }
    func testSelectionRejectsUnknownAndInvalidProbabilities() throws {
        let values = candidates(fixture()); let id = values[0].id
        XCTAssertThrowsError(try GroceryDecisionContract.selected([UUID(): 1], candidates: values))
        for value in [Double.nan, Double.infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try GroceryDecisionContract.selected([id: value], candidates: values))
        }
        XCTAssertTrue(try GroceryDecisionContract.selected([id: 0.5], candidates: values).isEmpty)
        XCTAssertEqual(try GroceryDecisionContract.selected([id: 0.9], candidates: values), [id])
    }
    func testOpenAIAndJevDecisionDecoding() throws {
        let values = candidates(fixture())
        let openAI = Data(#"{"model":"gpt-6-luna","answers":[{"name":"p0","type":"predicate","probability":0.95}]}"#.utf8)
        let jev = Data(#"{"model":"jev-latest","answers":{"p0":{"type":"noul","noul":0.95}}}"#.utf8)
        XCTAssertEqual(try GroceryDecisionClient.decode(openAI, provider: .openAI, candidates: values), [values[0].id])
        XCTAssertEqual(try GroceryDecisionClient.decode(jev, provider: .jev, candidates: values), [values[0].id])
    }
    func testRefusalAndMissingAnswersNeverBecomeSuggestions() throws {
        let values = candidates(fixture())
        for payload in [#"{"model":"gpt-6-luna","answers":[]}"#,
                        #"{"model":"gpt-6-luna","answers":[{"name":"p0","type":"refusal"}]}"#] {
            XCTAssertTrue(try GroceryDecisionClient.decode(Data(payload.utf8), provider: .openAI, candidates: values).isEmpty)
        }
    }
    func testUnknownDuplicateAndGenerativeAnswersRejected() {
        let values = candidates(fixture())
        for payload in [
            #"{"model":"gpt-6-luna","answers":[{"name":"p1","type":"predicate","probability":1}]}"#,
            #"{"model":"gpt-6-luna","answers":[{"name":"p0","type":"predicate","probability":1},{"name":"p0","type":"predicate","probability":1}]}"#,
            #"{"model":"gpt-6-luna","answers":[{"name":"p0","type":"output_text"}]}"#,
            #"{"model":"general-model","answers":[]}"#
        ] {
            XCTAssertThrowsError(try GroceryDecisionClient.decode(Data(payload.utf8), provider: .openAI, candidates: values))
        }
    }
    func testResultSyncRoutingAndTombstone() throws {
        var data = fixture()
        let batch = GroceryDecisionBatch(listID: ShoppingList.defaultID, revision: "revision", generatedAt: now,
            provider: .jev, sponsor: "חיים", sponsorID: "device", recommendations: [data.products[0].id])
        data.decisionBatches = [batch]
        let key = "decision_\(batch.listID.uuidString)"
        XCTAssertTrue(SharedListBinding.keys(in: data, listID: batch.listID).contains(key))
        var journal = SyncJournal(); journal.seed(data, at: now)
        var receiver = ShoppingData(); var remoteJournal = SyncJournal()
        for revision in journal.revisions.values { _ = remoteJournal.merge(revision, into: &receiver) }
        XCTAssertEqual(receiver.decisionBatches, [batch])
        let before = data; data.decisionBatches = []
        journal.recordChanges(from: before, to: data, at: now.addingTimeInterval(1))
        XCTAssertTrue(remoteJournal.merge(try XCTUnwrap(journal.revisions[key]), into: &receiver))
        XCTAssertTrue(receiver.decisionBatches.isEmpty)
    }
    func testOlderDataDecodesWithoutDecisionFeature() throws {
        let data = try JSONDecoder().decode(ShoppingData.self, from: Data("{}".utf8))
        XCTAssertTrue(data.decisionBatches.isEmpty)
        XCTAssertNil(data.lists.first?.decisionRecommendations)
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
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

extension GroceryDecisionTests {
    func testBothRequestsUseDecisionOnlyRoutesAndOpaqueLabels() async throws {
        let values = candidates(fixture())
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroceryDecisionMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); GroceryDecisionMockProtocol.respond = nil }
        for provider in GroceryDecisionProvider.allCases {
            GroceryDecisionMockProtocol.respond = { request in
                XCTAssertEqual(request.url, provider.endpoint)
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
                let body = try XCTUnwrap(request.httpBody)
                let text = String(decoding: body, as: UTF8.self)
                XCTAssertFalse(text.contains(values[0].id.uuidString))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["model"] as? String, provider.model)
                XCTAssertNil(json["messages"])
                if provider == .openAI {
                    XCTAssertNotNil(json["input"])
                    return (200, Data(#"{"model":"gpt-6-luna","answers":[{"name":"p0","type":"predicate","probability":0.9}]}"#.utf8))
                } else {
                    XCTAssertNotNil(json["state"])
                    return (200, Data(#"{"model":"jev-latest","answers":{"p0":{"type":"noul","noul":0.9}}}"#.utf8))
                }
            }
            let result = try await GroceryDecisionClient(session: session).evaluate(
                provider: provider, key: "synthetic-key", candidates: values)
            XCTAssertEqual(result, [values[0].id])
        }
    }
    func testQuotaErrorNeverFallsBackOrExposesUpstreamBody() async throws {
        var calls = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroceryDecisionMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); GroceryDecisionMockProtocol.respond = nil }
        GroceryDecisionMockProtocol.respond = { _ in
            calls += 1
            return (429, Data("sensitive upstream diagnostic".utf8))
        }
        do {
            _ = try await GroceryDecisionClient(session: session).evaluate(
                provider: .openAI, key: "synthetic-key", candidates: candidates(fixture()))
            XCTFail("Expected quota error")
        } catch {
            guard case GroceryDecisionError.quota = error else { return XCTFail("Wrong error") }
            XCTAssertFalse(error.localizedDescription.contains("sensitive"))
        }
        XCTAssertEqual(calls, 1)
    }
}
