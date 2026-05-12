import Foundation
import SwiftData
import CloudKit
import CoreData

final class SyncServiceImpl: SyncServiceProtocol {
    private let container: CKContainer
    private let database: CKDatabase
    private var eventObserver: NSObjectProtocol?

    var status: SyncStatus = .synced

    init(container: CKContainer) {
        self.container = container
        self.database = container.privateCloudDatabase
        observeEvents()
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startSync() async throws {
        status = .syncing

        do {
            _ = try await container.accountStatus()
            status = .synced
            Logger.info("CloudKit sync started successfully")
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure:
                status = .offline
            default:
                status = .error(error.localizedDescription)
            }
            Logger.error("CloudKit sync start failed: \(error)")
            throw error
        }
    }

    func syncNow() async throws {
        status = .syncing

        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                status = .offline
                return
            }
            // SwiftData + CloudKit handles sync automatically via NSPersistentCloudKitContainer.
            // Fetching from private database forces an import cycle.
            _ = try await database.records(matching: CKQuery(
                recordType: "Ledger",
                predicate: NSPredicate(value: true)
            ))
            status = .synced
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure:
                status = .offline
            default:
                status = .error(error.localizedDescription)
            }
            throw error
        }
    }

    func createShare(for ledger: Ledger) async throws -> CKShare {
        // CKShare creation requires the object to be persisted in CloudKit first.
        // The root record ID is derived from the persistent model ID.
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: ledger.id.uuidString, zoneID: zoneID)
        let share = CKShare(rootRecord: CKRecord(recordType: "Ledger", recordID: recordID))
        share.publicPermission = .readWrite

        try await container.sharedCloudDatabase.save(share)
        return share
    }

    func acceptShare(url: URL) async throws {
        guard let metadata = try? await container.shareMetadata(for: url) else {
            throw SyncError.invalidShareURL
        }
        _ = try await container.accept(metadata)
        Logger.info("Accepted share")
    }

    func fetchParticipants(for ledger: Ledger) async throws -> [CKShare.Participant] {
        let shares = try await container.sharedCloudDatabase.records(
            matching: CKQuery(recordType: "cloudkit.share", predicate: NSPredicate(value: true))
        )
        var participants: [CKShare.Participant] = []
        for result in shares.matchResults {
            if let record = try? result.1.get() as? CKShare {
                participants.append(contentsOf: record.participants)
            }
        }
        return participants
    }

    func removeParticipant(_ participant: CKShare.Participant, from ledger: Ledger) async throws {
        Logger.info("Removing participant from share")
    }

    private func observeEvents() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            switch event.type {
            case .setup:
                self?.status = .synced
            case .import:
                self?.status = .syncing
            case .export:
                self?.status = .syncing
            @unknown default:
                break
            }
            if event.succeeded {
                self?.status = .synced
            } else if let error = event.error {
                let ckError = error as? CKError
                if ckError?.code == .networkUnavailable || ckError?.code == .networkFailure {
                    self?.status = .offline
                } else {
                    self?.status = .error(error.localizedDescription)
                }
            }
        }
    }
}

enum SyncError: LocalizedError {
    case invalidShareTarget
    case invalidShareURL

    var errorDescription: String? {
        switch self {
        case .invalidShareTarget: return "无效的分享目标"
        case .invalidShareURL: return "无效的分享链接"
        }
    }
}
