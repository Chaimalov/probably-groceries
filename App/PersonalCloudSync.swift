import CloudKit
import Foundation

// The app's JSON store remains the source used by the UI. A foreground pass
// reconciles stable entity records with the private iCloud database. No network
// result is allowed to replace the entire local shopping file.
@MainActor
final class PersonalCloudSync: ObservableObject {
    enum Status: Equatable {
        case local, syncing, current, unavailable, accountChanged, failed
    }

    private(set) var status: Status = .local {
        didSet { store?.updateSyncStatus(status) }
    }
    private weak var store: ShoppingStore?
    private var container: CKContainer { CKContainer(identifier: "iCloud.com.chaimalov.probablygroceries") }
    private let zone = CKRecordZone(zoneName: "Groceries")
    private var started = false
    private var syncing = false
    private var needsAnotherPass = false
    private var scheduled: Task<Void, Never>?

    init(store: ShoppingStore) { self.store = store }

    func start() {
        started = true
        schedule()
    }

    func schedule() {
        guard started else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    func synchronize() async {
        if syncing { needsAnotherPass = true; return }
        guard let store else { return }
        syncing = true
        status = .syncing
        defer {
            syncing = false
            if needsAnotherPass {
                needsAnotherPass = false
                schedule()
            }
        }
        do {
            guard try await container.accountStatus() == .available else {
                status = .unavailable
                return
            }
            let accountID = try await container.userRecordID().recordName
            if let bound = store.syncJournal.accountRecordName, bound != accountID {
                // Never silently copy one person's groceries to another Apple Account.
                status = .accountChanged
                return
            }
            if store.syncJournal.accountRecordName == nil {
                store.syncJournal.accountRecordName = accountID
                store.saveSyncMetadata()
            }

            let database = container.privateCloudDatabase
            if !store.syncJournal.zoneReady {
                _ = try await database.save(zone)
                store.syncJournal.zoneReady = true
                store.saveSyncMetadata()
            }

            var remote: [String: (SyncRevision, CKRecord)] = [:]
            let query = CKQuery(recordType: "ShoppingEntity", predicate: NSPredicate(value: true))
            do {
                var page = try await database.records(matching: query, inZoneWith: zone.zoneID,
                                                      desiredKeys: ["modifiedAt", "payload", "deleted"],
                                                      resultsLimit: 200)
                while true {
                    for (_, result) in page.matchResults {
                        let record = try result.get()
                        guard let date = record["modifiedAt"] as? Date else { continue }
                        let deleted = (record["deleted"] as? NSNumber)?.boolValue == true
                        let revision = SyncRevision(key: record.recordID.recordName, modifiedAt: date,
                                                    payload: deleted ? nil : record["payload"] as? Data)
                        remote[revision.key] = (revision, record)
                    }
                    guard let cursor = page.queryCursor else { break }
                    page = try await database.records(continuingMatchFrom: cursor,
                                                      desiredKeys: ["modifiedAt", "payload", "deleted"],
                                                      resultsLimit: 200)
                }
            } catch let error as CKError where error.code == .unknownItem {
                // A brand-new container has no ShoppingEntity record type yet.
            }
            store.mergeRemote(remote.values.map(\.0))

            // Newly modified local records and tombstones are retried on every
            // pass. A failed upload leaves the local journal untouched.
            for local in store.syncJournal.revisions.values.sorted(by: { $0.key < $1.key }) {
                if let server = remote[local.key], server.0.modifiedAt >= local.modifiedAt { continue }
                var base = remote[local.key]?.1 ?? CKRecord(recordType: "ShoppingEntity",
                    recordID: CKRecord.ID(recordName: local.key, zoneID: zone.zoneID))
                for attempt in 0..<2 {
                    base["modifiedAt"] = local.modifiedAt as NSDate
                    base["deleted"] = NSNumber(value: local.payload == nil)
                    base["payload"] = local.payload as NSData?
                    do {
                        _ = try await database.save(base)
                        break
                    } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                        guard let server = error.serverRecord,
                              let serverDate = server["modifiedAt"] as? Date else { throw error }
                        if serverDate >= local.modifiedAt {
                            let deleted = (server["deleted"] as? NSNumber)?.boolValue == true
                            store.mergeRemote([SyncRevision(key: local.key, modifiedAt: serverDate,
                                payload: deleted ? nil : server["payload"] as? Data)])
                            break
                        }
                        base = server
                    }
                }
            }
            status = .current
        } catch {
            // Offline and service failures leave the journal and shopping UI intact.
            status = .failed
        }
    }
}
