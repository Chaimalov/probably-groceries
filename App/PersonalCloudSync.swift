import CloudKit
import Foundation
import OSLog
import UIKit

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
    // Local persistence constructs this coordinator even in unsigned simulator
    // builds. Defer CloudKit entitlement checks until a real sync/share request.
    lazy var container = CKContainer(identifier: PersonalCloudSync.containerIdentifier)
    private(set) var status: Status = .local {
        didSet { store?.updateSyncStatus(status) }
    }
    private weak var store: ShoppingStore?
    private let personalZone = CKRecordZone(zoneName: "Groceries")
    private var started = false
    private var syncTask: Task<Void, Never>?
    private var retryDelay: TimeInterval?
    private var subscriptionsReady = false
    private let changes = CloudZoneCache()
    private let logger = Logger(subsystem: "com.chaimalov.probablygroceries", category: "CloudSync")
    private var needsAnotherPass = false
    private var scheduled: Task<Void, Never>?

    init(store: ShoppingStore) { self.store = store }
    func start() { started = true; schedule(after: 0) }
    func schedule(after delay: TimeInterval = 0.2) {
        guard started else { return }
        if syncTask != nil { needsAnotherPass = true; return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            // Do not let a later edit cancel a CloudKit operation already running.
            self.scheduled = nil
            await self.synchronize()
        }
    }

    // All callers (including a watch request or silent push) await the same
    // in-flight work. Edits arriving during it get a further pass before return.
    func synchronize() async {
        started = true
        if let syncTask {
            needsAnotherPass = true
            await syncTask.value
            return
        }
        scheduled?.cancel()
        scheduled = nil
        let task = Task {
            let lease = CloudSyncBackgroundLease()
            defer { lease.end() }
            repeat {
                self.needsAnotherPass = false
                await self.performSync()
            } while self.needsAnotherPass && self.status == .current
        }
        syncTask = task
        await task.value
        syncTask = nil
        if let delay = retryDelay {
            retryDelay = nil
            schedule(after: delay)
        }
    }

    private func installSubscriptions() async {
        guard !subscriptionsReady else { return }
        do {
            for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
                let subscription = CKDatabaseSubscription(subscriptionID: "shopping-database-v1")
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info
                _ = try await database.save(subscription)
            }
            subscriptionsReady = true
        } catch {
            // A push registration failure must not prevent normal shopping sync.
            logger.error("CloudKit subscription registration failed: \(error.localizedDescription, privacy: .public)")
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

    private func performSync() async {
        guard let store else { return }
        status = .syncing
        do {
            try await verifyAccount()
            await installSubscriptions()
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
        } catch {
            status = .failed
            retryDelay = max(5, min((error as? CKError)?.retryAfterSeconds ?? 10, 300))
            logger.error("CloudKit sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upload(database: CKDatabase, zoneID: CKRecordZone.ID,
                        remote: [String: (SyncRevision, CKRecord)], keys: Set<String>) async throws {
        guard let store else { return }
        // Snapshot revisions before awaiting so an edit made during upload is
        // sent by the next pass, rather than being marked as already uploaded.
        let pending = store.syncJournal.revisions.values.filter { local in
            keys.contains(local.key) && (remote[local.key].map { Self.preferred(local, over: $0.0) } ?? true)
        }.sorted { $0.key < $1.key }
        for offset in stride(from: 0, to: pending.count, by: 50) {
            let batch = Array(pending[offset..<min(offset + 50, pending.count)])
            let records = batch.map { local in
                let record = remote[local.key]?.1 ?? CKRecord(recordType: "ShoppingEntity",
                    recordID: CKRecord.ID(recordName: local.key, zoneID: zoneID))
                record["modifiedAt"] = local.modifiedAt as NSDate
                record["deleted"] = NSNumber(value: local.payload == nil)
                record["payload"] = local.payload as NSData?
                return record
            }
            let results = try await saveBatch(records, database: database)
            for (local, record) in zip(batch, records) {
                guard let result = results[record.recordID] else { throw SharingError.syncFailed }
                switch result {
                case .success: break
                case .failure(let error):
                    guard let conflict = error as? CKError, conflict.code == .serverRecordChanged,
                          let server = conflict.serverRecord, let revision = Self.revision(server) else { throw error }
                    if Self.preferred(local, over: revision) {
                        server["modifiedAt"] = local.modifiedAt as NSDate
                        server["deleted"] = NSNumber(value: local.payload == nil)
                        server["payload"] = local.payload as NSData?
                        _ = try await database.save(server)
                    } else { store.mergeRemote([revision]) }
                }
            }
        }
    }

    private func saveBatch(_ records: [CKRecord], database: CKDatabase) async throws
        -> [CKRecord.ID: Result<CKRecord, Error>] {
        do {
            return try await database.modifyRecords(saving: records, deleting: [],
                savePolicy: .ifServerRecordUnchanged, atomically: false).saveResults
        } catch let error as CKError where error.code == .limitExceeded && records.count > 1 {
            let middle = records.count / 2
            let first = try await saveBatch(Array(records[..<middle]), database: database)
            let second = try await saveBatch(Array(records[middle...]), database: database)
            return first.merging(second) { _, new in new }
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

    private func fetchRecords(database: CKDatabase, zoneID: CKRecordZone.ID) async throws
        -> [String: (SyncRevision, CKRecord)] {
        let records = try await changes.fetch(database: database, zoneID: zoneID)
        var result: [String: (SyncRevision, CKRecord)] = [:]
        for record in records {
            if let revision = Self.revision(record) { result[revision.key] = (revision, record) }
        }
        return result
    }

    private func finishSync() async throws {
        await synchronize()
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

// Keep phone work alive after replying to the watch or leaving the UI. The
// local journal and zone checkpoint remain safe if iOS expires this budget.
@MainActor
private final class CloudSyncBackgroundLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Shopping sync") { [weak self] in
            self?.end()
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
