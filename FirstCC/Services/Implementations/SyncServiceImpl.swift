import Foundation
import SwiftData
import CloudKit
import CoreData

final class SyncServiceImpl: SyncServiceProtocol {
    private let ckContainer: CKContainer
    private let modelContainer: ModelContainer
    private let database: CKDatabase
    private var eventObserver: NSObjectProtocol?
    private weak var persistentContainer: NSPersistentCloudKitContainer?

    var status: SyncStatus = .synced

    init(container: CKContainer, modelContainer: ModelContainer) {
        self.ckContainer = container
        self.modelContainer = modelContainer
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
        guard let container = persistentContainer else {
            throw SyncError.shareContainerNotReady
        }

        let context = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
        fetch.predicate = NSPredicate(format: "id == %@", ledger.id as CVarArg)
        fetch.fetchLimit = 1
        guard let nsObject = try context.fetch(fetch).first else {
            throw SyncError.invalidShareTarget
        }

        let objectID = nsObject.objectID
        let storeContainer = container

        return try await Task.detached(priority: .userInitiated) {
            let bgContext = storeContainer.newBackgroundContext()
            let bgObject = bgContext.object(with: objectID)
            bgObject.setValue(true, forKey: "isShared")
            try bgContext.save()
            let (_, share, ckContainer) = try await storeContainer.share([bgObject], to: nil)
            Logger.info("CKShare created: \(share.recordID)")
            return share
        }.value
    }

    @MainActor
    func acceptShare(metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("SyncService.acceptShare: delegating to CloudKitShareCoordinator")
        try await CloudKitShareCoordinator.shared.accept(metadata)
        NotificationCenter.default.post(name: .shareAccepted, object: nil)
    }

    @MainActor
    func importSharedData(into modelContainer: ModelContainer) async throws -> [Ledger] {
        DiagnosticLog.log("SyncService.importSharedData: polling for shared data...")

        let coordinator = CloudKitShareCoordinator.shared

        for attempt in 1...30 {
            let hasData = try await coordinator.pollForLedgers()
            DiagnosticLog.log("importSharedData poll [\(attempt)]: hasData=\(hasData)")

            if hasData {
                DiagnosticLog.log("importSharedData: data found, importing...")
                let container = try await coordinator.containerForImport()
                let imported = try await SharedLedgerImportService.shared.importSharedLedgers(
                    from: container,
                    into: modelContainer
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

            if let container = notification.object as? NSPersistentCloudKitContainer {
                self.persistentContainer = container
            }

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
