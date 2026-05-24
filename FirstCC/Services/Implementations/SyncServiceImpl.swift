import Foundation
@preconcurrency import CoreData
import CloudKit

final class SyncServiceImpl: SyncServiceProtocol {
    private let ckContainer: CKContainer
    private let coreDataStack: CoreDataStack
    private let database: CKDatabase
    private var eventObserver: NSObjectProtocol?

    var status: SyncStatus = .synced

    init(container: CKContainer, coreDataStack: CoreDataStack) {
        self.ckContainer = container
        self.coreDataStack = coreDataStack
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
            _ = try await ckContainer.accountStatus()
            status = .synced
            Logger.info("CloudKit sync started successfully")
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure: status = .offline
            default: status = .error(error.localizedDescription)
            }
            Logger.error("CloudKit sync start failed: \(error)")
            throw error
        }
    }

    func syncNow() async throws {
        status = .syncing
        do {
            let accountStatus = try await ckContainer.accountStatus()
            guard accountStatus == .available else { status = .offline; return }
            _ = try await database.records(matching: CKQuery(recordType: "Ledger", predicate: NSPredicate(value: true)))
            status = .synced
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure: status = .offline
            default: status = .error(error.localizedDescription)
            }
            throw error
        }
    }

    @MainActor
    func createShare(for ledger: Ledger) async throws -> CKShare {
        DiagnosticLog.log("SyncService.createShare: using CloudKitShareCoordinator")
        return try await CloudKitShareCoordinator.shared.createShare(
            ledgerID: ledger.id,
            name: ledger.name
        )
    }

    @MainActor
    func acceptShare(metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("SyncService.acceptShare: delegating to CloudKitShareCoordinator")
        try await CloudKitShareCoordinator.shared.accept(metadata)
        NotificationCenter.default.post(name: .shareAccepted, object: nil)
    }

    @MainActor
    func importSharedData(into stack: CoreDataStack) async throws -> [Ledger] {
        DiagnosticLog.log("SyncService.importSharedData: polling for shared data...")

        let coordinator = CloudKitShareCoordinator.shared

        for attempt in 1...30 {
            let hasData = try await coordinator.pollForLedgers()
            DiagnosticLog.log("importSharedData poll [\(attempt)]: hasData=\(hasData)")

            if hasData {
                DiagnosticLog.log("importSharedData: data found, importing...")
                let container = try await coordinator.containerForImport()
                let sharedStore = try await coordinator.sharedStoreForImport()
                let imported = try await SharedLedgerImportService.shared.importSharedLedgers(
                    from: container,
                    sharedStore: sharedStore,
                    into: stack.viewContext
                )
                DiagnosticLog.log("importSharedData: imported \(imported.count) ledger(s)")
                return imported
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        DiagnosticLog.log("importSharedData: TIMEOUT after 60s")
        throw SyncError.shareContainerNotReady
    }

    func fetchParticipants(for ledger: Ledger) async throws -> [CKShare.Participant] {
        let shares = try await ckContainer.sharedCloudDatabase.records(
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

    @MainActor
    func syncParticipants(metadata: CKShare.Metadata, for ledger: Ledger) async throws {
        DiagnosticLog.log("SyncService.syncParticipants: begin share=\(metadata.share.recordID)")
        let context = coreDataStack.viewContext
        let participants = metadata.share.participants

        let fetch = NSFetchRequest<User>(entityName: "User")
        let allUsers = try context.fetch(fetch)
        let existingUsers = allUsers.filter { $0.ledger?.id == ledger.id }
        var existingByRecordID = Dictionary(uniqueKeysWithValues: existingUsers.map { ($0.cloudKitUserRecordID, $0) })

        for participant in participants {
            let recordID = participant.userIdentity.lookupInfo?.userRecordID?.recordName ?? ""
            let name = participant.userIdentity.nameComponents?.formatted(.name(style: .abbreviated)) ?? "共享成员"
            let role: LedgerRole = participant.role == .owner ? .owner : .member
            DiagnosticLog.log("SyncService.syncParticipants: participant recordID=\(recordID) name=\(name) role=\(role.rawValue)")

            if recordID.isEmpty { continue }

            if let existing = existingByRecordID[recordID] {
                existing.displayName = name
                existing.role = role
                DiagnosticLog.log("SyncService.syncParticipants: updated existing user \(name)")
            } else {
                let user = User(displayName: name, cloudKitUserRecordID: recordID, role: role, context: context)
                user.ledger = ledger
                existingByRecordID[recordID] = user
                DiagnosticLog.log("SyncService.syncParticipants: created user \(name)")
            }
        }

        if context.hasChanges {
            try context.save()
            DiagnosticLog.log("SyncService.syncParticipants: saved users")
        }
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
            guard let self else { return }

            guard let event = notification.userInfo?["event"] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            if event.succeeded {
                self.status = .synced
            } else if let error = event.error {
                let ckError = error as? CKError
                if ckError?.code == .networkUnavailable || ckError?.code == .networkFailure {
                    self.status = .offline
                } else {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }
}

extension Notification.Name {
    static let shareAccepted = Notification.Name("shareAccepted")
}

enum SyncError: LocalizedError {
    case invalidShareTarget
    case invalidShareURL
    case shareContainerNotReady

    var errorDescription: String? {
        switch self {
        case .invalidShareTarget: return "无效的分享目标"
        case .invalidShareURL: return "无效的分享链接"
        case .shareContainerNotReady: return "同步未就绪，请确认 iCloud 已登录且网络正常"
        }
    }
}
