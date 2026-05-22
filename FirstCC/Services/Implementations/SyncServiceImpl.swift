import Foundation
import SwiftData
import CloudKit
import CoreData

final class SyncServiceImpl: SyncServiceProtocol {
    private let container: CKContainer
    private let modelContainer: ModelContainer
    private let database: CKDatabase
    private var eventObserver: NSObjectProtocol?
    private weak var persistentContainer: NSPersistentCloudKitContainer?
    private var pendingShareMetadata: CKShare.Metadata?

    var status: SyncStatus = .synced

    init(container: CKContainer, modelContainer: ModelContainer) {
        self.container = container
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

    @MainActor
    func createShare(for ledger: Ledger) async throws -> CKShare {
        guard let container = persistentContainer else {
            throw SyncError.shareContainerNotReady
        }

        // Fetch the NSManagedObject on the main context
        let context = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
        fetch.predicate = NSPredicate(format: "id == %@", ledger.id as CVarArg)
        fetch.fetchLimit = 1
        guard let nsObject = try context.fetch(fetch).first else {
            throw SyncError.invalidShareTarget
        }

        let objectID = nsObject.objectID
        let storeContainer = container

        // Run share() on a background context to avoid main-actor contention
        return try await Task.detached(priority: .userInitiated) {
            let bgContext = storeContainer.newBackgroundContext()
            let bgObject = bgContext.object(with: objectID)
            let (_, share, ckContainer) = try await storeContainer.share([bgObject], to: nil)
            Logger.info("CKShare container: \(ckContainer.containerIdentifier ?? "nil")")
            Logger.info("CKShare URL: \(share.url?.absoluteString ?? "nil")")
            Logger.info("CKShare recordID: \(share.recordID)")
            return share
        }.value
    }

    func acceptShare(url: URL) async throws {
        guard let metadata = try? await container.shareMetadata(for: url) else {
            throw SyncError.invalidShareURL
        }

        // Accept at CloudKit level immediately (so participant appears)
        try await container.accept(metadata)
        Logger.info("CloudKit share metadata accepted")

        // Try to set up CoreData shared store — wait for persistentContainer
        let deadline = Date().addingTimeInterval(30)
        while persistentContainer == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        if let ckContainer = persistentContainer,
           let store = ckContainer.persistentStoreCoordinator.persistentStores.first {
            try await acceptShareInvitations(into: store, container: ckContainer, metadata: metadata)
        } else {
            // Store metadata; observer will retry when container becomes available
            pendingShareMetadata = metadata
            Logger.info("Share deferred — waiting for persistentContainer")
        }
    }

    private func acceptShareInvitations(
        into store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        metadata: CKShare.Metadata
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: store) { objects, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        Logger.info("Accepted share via NSPersistentCloudKitContainer")
        pendingShareMetadata = nil

        // Notify app to refresh ledgers
        await MainActor.run {
            NotificationCenter.default.post(name: .shareAccepted, object: nil)
        }
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
            guard let self else { return }

            if let container = notification.object as? NSPersistentCloudKitContainer {
                let isFirstCapture = self.persistentContainer == nil
                self.persistentContainer = container

                // Process any pending share now that container is available
                if isFirstCapture, let metadata = self.pendingShareMetadata,
                   let store = container.persistentStoreCoordinator.persistentStores.first {
                    Task { [weak self, metadata] in
                        guard let self else { return }
                        do {
                            try await self.acceptShareInvitations(into: store, container: container, metadata: metadata)
                        } catch {
                            Logger.error("Deferred share accept failed: \(error)")
                        }
                    }
                }
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
