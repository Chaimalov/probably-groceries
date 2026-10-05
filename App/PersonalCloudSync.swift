import CloudKit
import Foundation

@MainActor
final class PersonalCloudSync: ObservableObject {
    enum Status: Equatable { case local, syncing, current, unavailable, accountChanged, failed }
    enum SharingError: LocalizedError {
        case unavailable, accountChanged, syncFailed, accessRemoved, wrongContainer
        var errorDescription: String? {
            switch self {
            case .unavailable: return "יש להתחבר ל־iCloud כדי לשתף רשימה."
            case .accountChanged: return "חשבון iCloud השתנה. הנתונים נשמרו במכשיר והשיתוף מושהה."
            case .syncFailed: return "לא הצלחנו לסנכרן את הרשימה. נסו שוב כשיש חיבור לאינטרנט."
            case .accessRemoved: return "הגישה לרשימה המשותפת אינה זמינה. השינויים נשמרו במכשיר."
            case .wrongContainer: return "ההזמנה אינה שייכת לאפליקציה הזו."
            }
        }
    }
    static let containerIdentifier = "iCloud.com.chaimalov.probablygroceries"
    let container = CKContainer(identifier: containerIdentifier)
    private(set) var status: Status = .local {
        didSet { store?.updateSyncStatus(status) }
    }
    private weak var store: ShoppingStore?
    private let personalZone = CKRecordZone(zoneName: "Groceries")
    private var started = false
    private var syncing = false
    private var needsAnotherPass = false
    private var scheduled: Task<Void, Never>?

    init(store: ShoppingStore) { self.store = store }
    func start() { started = true; schedule() }
    func schedule() {
        guard started else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    private func verifyAccount() async throws {
        guard let store else { throw SharingError.syncFailed }
        guard try await container.accountStatus() == .available else { throw SharingError.unavailable }
        let accountID = try await container.userRecordID().recordName
        if let bound = store.syncJournal.accountRecordName, bound != accountID {
            throw SharingError.accountChanged
        }
        if store.syncJournal.accountRecordName == nil {
            store.syncJournal.accountRecordName = accountID
            store.saveSyncMetadata()
        }
    }

    func synchronize() async {
        if syncing { needsAnotherPass = true; return }
        guard let store else { return }
        syncing = true
        status = .syncing
        defer {
            syncing = false
            if needsAnotherPass { needsAnotherPass = false; schedule() }
        }
        do {
            try await verifyAccount()
            let privateDB = container.privateCloudDatabase
            if !store.syncJournal.zoneReady {
                _ = try await privateDB.save(personalZone)
                store.syncJournal.zoneReady = true
                store.saveSyncMetadata()
            }
            // Discover lists joined on this or another device on this account.
            let owned = try await privateDB.allRecordZones()
            let joined = try await container.sharedCloudDatabase.allRecordZones()
            for (zones, isOwner) in [(owned, true), (joined, false)] {
                for zone in zones {
                    guard let listID = SharedListBinding.listID(fromZoneName: zone.zoneID.zoneName) else { continue }
                    store.registerSharedList(SharedListBinding(listID: listID,
                        zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: isOwner))
                }
            }
            var missingAccess = false
            for var binding in store.sharedLists {
                let database = binding.isOwner ? privateDB : container.sharedCloudDatabase
                let zoneID = CKRecordZone.ID(zoneName: binding.zoneName, ownerName: binding.ownerName)
                if binding.isOwner {
                    if !owned.contains(where: { $0.zoneID == zoneID }) {
                        _ = try await privateDB.save(CKRecordZone(zoneID: zoneID))
                    }
                } else if !joined.contains(where: { $0.zoneID == zoneID }) {
                    binding.accessible = false
                    store.registerSharedList(binding)
                    missingAccess = true
                    continue
                }
                let remote = try await fetchRecords(database: database, zoneID: zoneID)
                binding.keys.formUnion(remote.keys)
                binding.accessible = true
                store.registerSharedList(binding)
                store.mergeRemote(remote.values.map(\.0))
                binding.includeRecords(in: store.data)
                store.registerSharedList(binding)
                try await upload(database: database, zoneID: zoneID, remote: remote, keys: binding.keys)
            }
            // Joined records never upload into the participant's private DB.
            let fetchedPersonal = try await fetchRecords(database: privateDB, zoneID: personalZone.zoneID)
            // Local edits can happen during the fetch. Resolve routing only
            // after it completes so a newly added shared item cannot leak.
            let sharedKeys = store.sharedLists.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
            let personal = fetchedPersonal.filter { !sharedKeys.contains($0.key) }
            store.mergeRemote(personal.values.map(\.0))
            let personalKeys = Set(store.syncJournal.revisions.keys).subtracting(sharedKeys)
            try await upload(database: privateDB, zoneID: personalZone.zoneID, remote: personal, keys: personalKeys)
            status = missingAccess ? .failed : .current
        } catch SharingError.accountChanged { status = .accountChanged
        } catch SharingError.unavailable { status = .unavailable
        } catch { status = .failed }
    }

    private func upload(database: CKDatabase, zoneID: CKRecordZone.ID,
                        remote: [String: (SyncRevision, CKRecord)], keys: Set<String>) async throws {
        guard let store else { return }
        for local in store.syncJournal.revisions.values.filter({ keys.contains($0.key) })
            .sorted(by: { $0.key < $1.key }) {
            if let server = remote[local.key], !Self.preferred(local, over: server.0) { continue }
            var base = remote[local.key]?.1 ?? CKRecord(recordType: "ShoppingEntity",
                recordID: CKRecord.ID(recordName: local.key, zoneID: zoneID))
            for attempt in 0..<2 {
                base["modifiedAt"] = local.modifiedAt as NSDate
                base["deleted"] = NSNumber(value: local.payload == nil)
                base["payload"] = local.payload as NSData?
                do {
                    _ = try await database.save(base)
                    break
                } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                    guard let server = error.serverRecord, let revision = Self.revision(server) else { throw error }
                    if !Self.preferred(local, over: revision) {
                        store.mergeRemote([revision])
                        break
                    }
                    base = server
                }
            }
        }
    }

    private static func preferred(_ local: SyncRevision, over server: SyncRevision) -> Bool {
        local.modifiedAt > server.modifiedAt || (local.modifiedAt == server.modifiedAt &&
            (local.payload ?? Data()).lexicographicallyPrecedes(server.payload ?? Data()))
    }
    private static func revision(_ record: CKRecord) -> SyncRevision? {
        guard record.recordType == "ShoppingEntity", let date = record["modifiedAt"] as? Date else { return nil }
        let deleted = (record["deleted"] as? NSNumber)?.boolValue == true
        return SyncRevision(key: record.recordID.recordName, modifiedAt: date,
                            payload: deleted ? nil : record["payload"] as? Data)
    }

    // Zone changes support the shared DB and avoid query-index requirements.
    // This small v1 refetches from nil; tombstones remain regular records.
    private func fetchRecords(database: CKDatabase, zoneID: CKRecordZone.ID) async throws
        -> [String: (SyncRevision, CKRecord)] {
        let records: [CKRecord] = try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID],
                                                               configurationsByRecordZoneID: nil)
            operation.fetchAllChanges = true
            let collector = CloudRecordCollector()
            operation.recordWasChangedBlock = { _, result in collector.append(result) }
            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result { collector.fail(error) }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .failure(let error): continuation.resume(throwing: error)
                case .success: continuation.resume(with: collector.result())
                }
            }
            database.add(operation)
        }
        var result: [String: (SyncRevision, CKRecord)] = [:]
        for record in records {
            if let revision = Self.revision(record) { result[revision.key] = (revision, record) }
        }
        return result
    }

    private func finishSync() async throws {
        while syncing { try await Task.sleep(for: .milliseconds(100)) }
        await synchronize()
        while syncing { try await Task.sleep(for: .milliseconds(100)) }
        guard status == .current else {
            if status == .accountChanged { throw SharingError.accountChanged }
            if status == .unavailable { throw SharingError.unavailable }
            throw SharingError.syncFailed
        }
    }

    func prepareShare(for listID: UUID) async throws -> CKShare {
        guard let store else { throw SharingError.syncFailed }
        try await verifyAccount()
        try await finishSync()
        guard store.selectedListID == listID else { throw SharingError.syncFailed }
        let binding = store.prepareCurrentListForSharing(ownerName: CKCurrentUserDefaultName)
        guard binding.accessible else { throw SharingError.accessRemoved }
        try await finishSync()
        let database = binding.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: binding.zoneName, ownerName: binding.ownerName)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            guard let share = try await database.record(for: shareID) as? CKShare else { throw SharingError.syncFailed }
            return share
        } catch let error as CKError where error.code == .unknownItem && binding.isOwner {
            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = store.currentList.name as NSString
            share.publicPermission = .none
            guard let saved = try await database.save(share) as? CKShare else { throw SharingError.syncFailed }
            return saved
        }
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        guard metadata.containerIdentifier == Self.containerIdentifier else { throw SharingError.wrongContainer }
        try await verifyAccount()
        _ = try await container.accept(metadata)
        try await finishSync()
        if let listID = SharedListBinding.listID(fromZoneName: metadata.share.recordID.zoneID.zoneName) {
            store?.selectList(listID)
        }
    }
}

// CloudKit callbacks run outside the main actor. Partial results are failures.
private final class CloudRecordCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord] = []
    private var error: Error?
    func append(_ result: Result<CKRecord, Error>) {
        lock.lock(); defer { lock.unlock() }
        switch result {
        case .success(let record): records.append(record)
        case .failure(let failure): error = failure
        }
    }
    func fail(_ failure: Error) { lock.lock(); defer { lock.unlock() }; error = failure }
    func result() -> Result<[CKRecord], Error> {
        lock.lock(); defer { lock.unlock() }
        if let error { return .failure(error) }
        return .success(records)
    }
}
