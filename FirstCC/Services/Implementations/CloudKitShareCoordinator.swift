import Foundation
import CoreData
import CloudKit

/// Dedicated NSPersistentCloudKitContainer with ONLY a shared store.
/// Does NOT create a private store — avoids conflict with SwiftData's private-only container.
/// All store loading happens off the main thread to avoid watchdog crashes.
final class CloudKitShareCoordinator {
    static let shared = CloudKitShareCoordinator()

    private var _container: NSPersistentCloudKitContainer?
    private var _sharedStore: NSPersistentStore?
    private let initQueue = DispatchQueue(label: "com.qianey.cloudkit-coordinator")

    private init() {}

    // MARK: - Async lazy init (off main thread)

    private func ensureContainer() async throws -> NSPersistentCloudKitContainer {
        if let c = _container, let _ = _sharedStore { return c }

        return try await withCheckedThrowingContinuation { cont in
            initQueue.async {
                do {
                    let model = Self.buildSharedModel()

                    let container = NSPersistentCloudKitContainer(name: "SharedOnly", managedObjectModel: model)
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

                    let sharedURL = appSupport.appendingPathComponent("FirstCC.SharedOnly.sqlite")

                    let sharedDesc = NSPersistentStoreDescription(url: sharedURL)
                    sharedDesc.configuration = "Shared"
                    let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: CloudKitConfig.containerIdentifier)
                    sharedOptions.databaseScope = .shared
                    sharedDesc.cloudKitContainerOptions = sharedOptions

                    container.persistentStoreDescriptions = [sharedDesc]

                    var loadError: Error?
                    container.loadPersistentStores { _, error in
                        if let error { loadError = error }
                    }

                    if let error = loadError {
                        DiagnosticLog.log("CloudKitCoordinator: shared-only load failed: \(error.localizedDescription)")
                        cont.resume(throwing: error)
                        return
                    }

                    let stores = container.persistentStoreCoordinator.persistentStores
                    DiagnosticLog.log("CloudKitCoordinator: loaded \(stores.count) shared-only store(s)")
                    self._container = container
                    self._sharedStore = stores.first!
                    cont.resume(returning: container)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    func accept(_ metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("CloudKitCoordinator.accept: starting (shared-only, bg init)")

        let c = try await ensureContainer()
        guard let store = _sharedStore else {
            throw SyncError.shareContainerNotReady
        }

        let count = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            c.acceptShareInvitations(from: [metadata], into: store) { metadatas, error in
                if let error {
                    DiagnosticLog.log("CloudKitCoordinator.accept: error \(error.localizedDescription)")
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: metadatas?.count ?? 0)
                }
            }
        }

        DiagnosticLog.log("CloudKitCoordinator.accept: OK, accepted \(count) share(s)")
    }

    // MARK: - Polling (uses background context for thread safety)

    func pollForLedgers() async throws -> Bool {
        let c = try await ensureContainer()
        return try await withCheckedThrowingContinuation { cont in
            c.performBackgroundTask { ctx in
                let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
                let count = (try? ctx.count(for: fetch)) ?? 0
                cont.resume(returning: count > 0)
            }
        }
    }

    func containerForImport() async throws -> NSPersistentCloudKitContainer {
        try await ensureContainer()
    }

    // MARK: - Programmatic model (entities assigned to "Shared" config)

    private static func buildSharedModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let ledgerEntity = NSEntityDescription()
        ledgerEntity.name = "Ledger"
        ledgerEntity.managedObjectClassName = "Ledger"

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"; idAttr.attributeType = .UUIDAttributeType; idAttr.isOptional = false

        let nameAttr = NSAttributeDescription()
        nameAttr.name = "name"; nameAttr.attributeType = .stringAttributeType; nameAttr.isOptional = false

        let iconAttr = NSAttributeDescription()
        iconAttr.name = "iconName"; iconAttr.attributeType = .stringAttributeType; iconAttr.isOptional = true

        let typeAttr = NSAttributeDescription()
        typeAttr.name = "typeRaw"; typeAttr.attributeType = .stringAttributeType; typeAttr.isOptional = true

        let currencyAttr = NSAttributeDescription()
        currencyAttr.name = "defaultCurrencyCode"; currencyAttr.attributeType = .stringAttributeType; currencyAttr.isOptional = true

        let sharedAttr = NSAttributeDescription()
        sharedAttr.name = "isShared"; sharedAttr.attributeType = .booleanAttributeType; sharedAttr.isOptional = false

        let dateAttr = NSAttributeDescription()
        dateAttr.name = "createdAt"; dateAttr.attributeType = .dateAttributeType; dateAttr.isOptional = true

        let ownerAttr = NSAttributeDescription()
        ownerAttr.name = "ownerUserRecordID"; ownerAttr.attributeType = .stringAttributeType; ownerAttr.isOptional = true

        ledgerEntity.properties = [idAttr, nameAttr, iconAttr, typeAttr, currencyAttr, sharedAttr, dateAttr, ownerAttr]

        model.setEntities([ledgerEntity], forConfigurationName: "Shared")

        return model
    }
}
