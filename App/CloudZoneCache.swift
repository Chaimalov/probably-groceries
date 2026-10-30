import CloudKit
import Foundation

/// The cached records and their change token are one atomic checkpoint. A
/// crash before ShoppingStore merges it is safe: the next fetch returns the
/// complete cached state as well as any newer deltas. No token can skip data.
@MainActor
final class CloudZoneCache {
    private struct Checkpoint: Codable {
        let records: Data
        let token: Data?
    }
    private let file: URL
    private var checkpoints: [String: Checkpoint]

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cloud-zone-cache.json")
        checkpoints = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String: Checkpoint].self, from: $0) } ?? [:]
    }

    func fetch(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let key = "\(database.databaseScope.rawValue)/\(zoneID.ownerName)/\(zoneID.zoneName)"
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        if let checkpoint = checkpoints[key] {
            do {
                guard let savedRecords = try NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: CKRecord.self,
                    from: checkpoint.records) else { throw CocoaError(.coderReadCorrupt) }
                records = savedRecords
                if let data = checkpoint.token {
                    token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
                }
            } catch {
                // An unreadable checkpoint requires a full zone fetch.
                records = []
                token = nil
            }
        }
        // A full fetch has no deletion events for records removed before it;
        // never seed it from an older cache without a matching token.
        if token == nil { records = [] }
        let fetched: ([CKRecord], CKServerChangeToken?)
        do {
            fetched = try await fetchChanges(database: database, zoneID: zoneID, records: records, token: token)
        } catch let error as CKError where error.code == .changeTokenExpired {
            fetched = try await fetchChanges(database: database, zoneID: zoneID, records: [], token: nil)
        }
        let checkpoint = Checkpoint(
            records: try NSKeyedArchiver.archivedData(withRootObject: fetched.0, requiringSecureCoding: true),
            token: try fetched.1.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) })
        var updated = checkpoints
        updated[key] = checkpoint
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: file, options: [.atomic, .completeUntilFirstUserAuthentication])
        checkpoints = updated
        return fetched.0
    }

    private func fetchChanges(database: CKDatabase, zoneID: CKRecordZone.ID,
                              records: [CKRecord], token: CKServerChangeToken?) async throws
        -> ([CKRecord], CKServerChangeToken?) {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = token
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration])
            operation.fetchAllChanges = true
            operation.qualityOfService = .userInitiated
            let collector = CloudDeltaCollector(records: records, token: token)
            operation.recordWasChangedBlock = { _, result in collector.append(result) }
            operation.recordWithIDWasDeletedBlock = { id, _ in collector.remove(id) }
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let zone): collector.updateToken(zone.serverChangeToken)
                case .failure(let error): collector.fail(error)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .failure(let error): continuation.resume(throwing: collector.failure ?? error)
                case .success: continuation.resume(with: collector.result())
                }
            }
            database.add(operation)
        }
    }
}

// CloudKit serializes callbacks off the main actor. Protect values explicitly
// instead of mutating captured arrays in @Sendable callbacks.
private final class CloudDeltaCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord.ID: CKRecord]
    private var token: CKServerChangeToken?
    private var error: Error?
    init(records: [CKRecord], token: CKServerChangeToken?) {
        self.records = Dictionary(records.map { ($0.recordID, $0) }, uniquingKeysWith: { _, new in new })
        self.token = token
    }
    var failure: Error? { lock.lock(); defer { lock.unlock() }; return error }
    func append(_ result: Result<CKRecord, Error>) {
        lock.lock(); defer { lock.unlock() }
        switch result {
        case .success(let record): records[record.recordID] = record
        case .failure(let error): self.error = error
        }
    }
    func remove(_ id: CKRecord.ID) { lock.lock(); defer { lock.unlock() }; records[id] = nil }
    func updateToken(_ token: CKServerChangeToken?) { lock.lock(); defer { lock.unlock() }; self.token = token }
    func fail(_ error: Error) { lock.lock(); defer { lock.unlock() }; self.error = error }
    func result() -> Result<([CKRecord], CKServerChangeToken?), Error> {
        lock.lock(); defer { lock.unlock() }
        if let error { return .failure(error) }
        return .success((Array(records.values), token))
    }
}
