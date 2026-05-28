import Foundation
@preconcurrency import CoreData
import CloudKit

@MainActor
final class CoreDataStack: ObservableObject {
    static var shared: CoreDataStack!

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }
    var privateStore: NSPersistentStore {
        container.persistentStoreCoordinator.persistentStores.first { $0.url == privateURL }!
    }
    var sharedStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { $0.url == sharedURL }
    }

    private let privateURL: URL
    private let sharedURL: URL

    init() {
        guard let modelURL = Bundle.main.url(forResource: "FirstCC", withExtension: "momd") else {
            fatalError("CoreDataStack: FirstCC.momd not found")
        }
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("CoreDataStack: Failed to load NSManagedObjectModel")
        }

        container = NSPersistentCloudKitContainer(name: "FirstCC", managedObjectModel: model)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        privateURL = appSupport.appendingPathComponent("FirstCC.sqlite")
        sharedURL = appSupport.appendingPathComponent("FirstCC.shared.sqlite")

        let privateDescription = NSPersistentStoreDescription(url: privateURL)
        privateDescription.configuration = "Private"
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let sharedDescription = NSPersistentStoreDescription(url: sharedURL)
        sharedDescription.configuration = "Shared"
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // CloudKit event logging for sync diagnostics
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let storeLabel = event.storeIdentifier.split(separator: "/").last.map(String.init) ?? event.storeIdentifier
            let success = event.succeeded ? "OK" : "FAIL"
            let errorInfo: String
            if let err = event.error { errorInfo = " err=\(err.localizedDescription)" } else { errorInfo = "" }
            DiagnosticLog.log("CloudKit[\(storeLabel)] \(event.type.rawValue): \(success)\(errorInfo)")
        }

        DiagnosticLog.log("CoreDataStack: init complete (stores not loaded yet)")
    }

    func loadStores() async throws {
        DiagnosticLog.log("CoreDataStack: loadStores begin")
        let expectedCount = container.persistentStoreDescriptions.count
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var loadedCount = 0
            var lastError: Error?
            var resumed = false
            // Shared store callback may never fire if no iCloud shares accepted.
            // Proceed as soon as the Private store is loaded; Shared store loads async.
            let requiredCount = 1 // only wait for Private store
            container.loadPersistentStores { storeDescription, error in
                loadedCount += 1
                let fileName = storeDescription.url?.lastPathComponent ?? "unknown"
                let isPrivate = fileName.contains("FirstCC.sqlite") && !fileName.contains("shared")
                DiagnosticLog.log("CoreDataStack: store callback \(fileName) loaded=\(loadedCount)/\(expectedCount) private=\(isPrivate)")
                if let error {
                    let ns = error as NSError
                    DiagnosticLog.log("CoreDataStack: store \(fileName) FAILED: domain=\(ns.domain) code=\(ns.code)")
                    DiagnosticLog.log("CoreDataStack:   description=\(ns.localizedDescription)")
                    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                        DiagnosticLog.log("CoreDataStack:   underlying domain=\(underlying.domain) code=\(underlying.code) desc=\(underlying.localizedDescription)")
                    }
                    if let reason = ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                        DiagnosticLog.log("CoreDataStack:   reason=\(reason)")
                    }
                    if isPrivate { lastError = error }
                }
                if !resumed {
                    if isPrivate && lastError != nil {
                        resumed = true
                        continuation.resume(throwing: lastError!)
                    } else if isPrivate {
                        resumed = true
                        DiagnosticLog.log("CoreDataStack: Private store loaded, proceeding (Shared may still be pending)")
                        continuation.resume()
                    }
                }
            }
        }
        DiagnosticLog.log("CoreDataStack: loadStores complete")
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    // MARK: - CloudKit Sharing

    func createShareForLedger(id: UUID, name: String) async throws -> CKShare {
        DiagnosticLog.log("CoreDataStack: createShareForLedger id=\(id.uuidString.prefix(8)) name=\(name)")

        let context = container.viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        fetch.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetch.fetchLimit = 1

        let ledger: Ledger
        if let existing = try? context.fetch(fetch).first {
            DiagnosticLog.log("CoreDataStack: reusing existing ledger for share")
            ledger = existing
            ledger.name = name
        } else {
            DiagnosticLog.log("CoreDataStack: creating new ledger for share")
            ledger = Ledger(context: context)
            ledger.id = id
            ledger.name = name
            ledger.iconName = "house"
            ledger.typeRaw = "personal"
            ledger.defaultCurrencyCode = "CNY"
        }

        try context.save()
        DiagnosticLog.log("CoreDataStack: saved, calling share()")

        return try await withThrowingTaskGroup(of: CKShare.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.container.share([ledger], to: nil) { _, share, _, error in
                        if let error {
                            let nsError = error as NSError
                            DiagnosticLog.log("CoreDataStack: share failed domain=\(nsError.domain) code=\(nsError.code)")
                            continuation.resume(throwing: error)
                        } else if let share {
                            DiagnosticLog.log("CoreDataStack: share created recordID=\(share.recordID)")
                            continuation.resume(returning: share)
                        } else {
                            DiagnosticLog.log("CoreDataStack: share returned nil")
                            continuation.resume(throwing: NSError(domain: "CoreDataStack", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "share() returned nil"]))
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw NSError(domain: "CoreDataStack", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "共享操作超时，请检查iCloud设置和网络连接后重试"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func acceptShareInvitations(from metadata: CKShare.Metadata) async throws {
        guard let sharedStore = sharedStore else {
            throw NSError(domain: "CoreDataStack", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Shared store not loaded yet, retry later"])
        }
        DiagnosticLog.log("CoreDataStack: acceptShareInvitations begin")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: sharedStore) { acceptedShares, error in
                if let error {
                    DiagnosticLog.log("CoreDataStack: accept failed \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    DiagnosticLog.log("CoreDataStack: accept succeeded count=\(acceptedShares?.count ?? 0)")
                    continuation.resume()
                }
            }
        }
    }

    func fetchSharedLedgerCount() throws -> Int {
        guard let sharedStore = sharedStore else { return 0 }
        let context = container.viewContext
        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        fetch.affectedStores = [sharedStore]
        let count = try context.count(for: fetch)
        DiagnosticLog.log("CoreDataStack: shared ledger count=\(count)")
        return count
    }

    /// Destroy and recreate the shared store — used when a participant exits a share
    /// to prevent stale data from contaminating future share acceptances.
    func resetSharedStore() async throws {
        let coordinator = container.persistentStoreCoordinator
        if let old = sharedStore {
            try coordinator.remove(old)
            DiagnosticLog.log("CoreDataStack: removed shared store from coordinator")
        }
        // Delete SQLite + WAL + SHM files
        let fm = FileManager.default
        for ext in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: sharedURL.path + ext)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
                DiagnosticLog.log("CoreDataStack: deleted \(url.lastPathComponent)")
            }
        }
        // Re-add a fresh shared store
        let desc = NSPersistentStoreDescription(url: sharedURL)
        desc.configuration = "Shared"
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
        options.databaseScope = .shared
        desc.cloudKitContainerOptions = options
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            coordinator.addPersistentStore(with: desc) { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }
        DiagnosticLog.log("CoreDataStack: shared store recreated")
    }
}
