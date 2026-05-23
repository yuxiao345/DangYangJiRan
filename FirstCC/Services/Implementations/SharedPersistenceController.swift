import Foundation
import CoreData
import CloudKit

final class SharedPersistenceController {
    private static var _shared: SharedPersistenceController?

    @MainActor
    static func create() async throws -> SharedPersistenceController {
        if let existing = _shared { return existing }
        let instance = SharedPersistenceController()
        try await instance.loadStores()
        _shared = instance
        return instance
    }

    let container: NSPersistentCloudKitContainer
    var privateStore: NSPersistentStore {
        container.persistentStoreCoordinator.persistentStores.first { $0.url == privateURL }!
    }
    var sharedStore: NSPersistentStore {
        container.persistentStoreCoordinator.persistentStores.first { $0.url == sharedURL }!
    }

    private let privateURL: URL
    private let sharedURL: URL

    private init() {
        DiagnosticLog.log("SharedPersistenceController: init begin")

        let model = Self.buildModel()
        DiagnosticLog.log("SharedPersistenceController: model built")

        let persistenceContainer = NSPersistentCloudKitContainer(name: "FirstCCShared", managedObjectModel: model)
        DiagnosticLog.log("SharedPersistenceController: container created")

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        privateURL = appSupport.appendingPathComponent("FirstCC.private.sqlite")
        sharedURL = appSupport.appendingPathComponent("FirstCC.shared.sqlite")
        DiagnosticLog.log("SharedPersistenceController: URLs private=\(privateURL.lastPathComponent) shared=\(sharedURL.lastPathComponent)")

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
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        persistenceContainer.persistentStoreDescriptions = [privateDescription, sharedDescription]
        DiagnosticLog.log("SharedPersistenceController: store descriptions set")

        container = persistenceContainer
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        DiagnosticLog.log("SharedPersistenceController: init complete (stores loading async)")
    }

    private func loadStores() async throws {
        DiagnosticLog.log("SharedPersistenceController: loadStores begin")
        let expectedCount = container.persistentStoreDescriptions.count
        DiagnosticLog.log("SharedPersistenceController: expecting \(expectedCount) stores")
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var loadedCount = 0
            var lastError: Error?
            container.loadPersistentStores { storeDescription, error in
                loadedCount += 1
                let fileName = storeDescription.url?.lastPathComponent ?? "unknown"
                if let error {
                    let nsError = error as NSError
                    DiagnosticLog.log("SharedPersistenceController: store \(fileName) FAILED domain=\(nsError.domain) code=\(nsError.code)")
                    if let detail = nsError.userInfo[NSDetailedErrorsKey] {
                        DiagnosticLog.log("SharedPersistenceController: detail=\(detail)")
                    }
                    if lastError == nil { lastError = error }
                } else {
                    DiagnosticLog.log("SharedPersistenceController: loaded store \(fileName)")
                }
                if loadedCount == expectedCount {
                    if let error = lastError {
                        DiagnosticLog.log("SharedPersistenceController: loadStores finished with error")
                        continuation.resume(throwing: error)
                    } else {
                        DiagnosticLog.log("SharedPersistenceController: loadStores all \(expectedCount) loaded")
                        continuation.resume()
                    }
                }
            }
        }
        DiagnosticLog.log("SharedPersistenceController: loadStores complete")
    }

    func createShareForLedger(id: UUID, name: String) async throws -> CKShare {
        DiagnosticLog.log("SharedPersistenceController: createShareForLedger begin id=\(id.uuidString.prefix(8)) name=\(name)")

        let context = container.viewContext
        let ledger = NSEntityDescription.insertNewObject(forEntityName: "Ledger", into: context)
        ledger.setValue(id, forKey: "id")
        ledger.setValue(name, forKey: "name")
        ledger.setValue("house", forKey: "iconName")
        ledger.setValue("personal", forKey: "typeRaw")
        ledger.setValue("CNY", forKey: "defaultCurrencyCode")
        ledger.setValue(true, forKey: "isShared")
        ledger.setValue(Date(), forKey: "createdAt")

        try context.save()
        DiagnosticLog.log("SharedPersistenceController: saved temp ledger, calling share()")

        return try await withCheckedThrowingContinuation { continuation in
            container.share([ledger], to: nil) { _, share, _, error in
                if let error {
                    let nsError = error as NSError
                    DiagnosticLog.log("SharedPersistenceController: share failed domain=\(nsError.domain) code=\(nsError.code)")
                    continuation.resume(throwing: error)
                } else if let share {
                    DiagnosticLog.log("SharedPersistenceController: share created recordID=\(share.recordID)")
                    continuation.resume(returning: share)
                } else {
                    DiagnosticLog.log("SharedPersistenceController: share returned nil")
                    continuation.resume(throwing: NSError(domain: "SharedPersistence", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "share() returned nil"]))
                }
            }
        }
    }

    func acceptShareInvitations(from metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("SharedPersistenceController: acceptShareInvitations begin")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: sharedStore) { acceptedShares, error in
                if let error {
                    DiagnosticLog.log("SharedPersistenceController: accept failed \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    DiagnosticLog.log("SharedPersistenceController: accept succeeded count=\(acceptedShares?.count ?? 0)")
                    continuation.resume()
                }
            }
        }
    }

    func fetchSharedLedgerCount() throws -> Int {
        let context = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
        let count = try context.count(for: fetch)
        DiagnosticLog.log("SharedPersistenceController: shared ledger count=\(count)")
        return count
    }

    private static func buildModel() -> NSManagedObjectModel {
        DiagnosticLog.log("  buildModel: 0 start")
        let model = NSManagedObjectModel()
        DiagnosticLog.log("  buildModel: 1 NSManagedObjectModel created")

        let ledgerEntity = NSEntityDescription()
        DiagnosticLog.log("  buildModel: 2 NSEntityDescription created")
        ledgerEntity.name = "Ledger"
        DiagnosticLog.log("  buildModel: 3 name set")
        ledgerEntity.managedObjectClassName = "NSManagedObject"
        DiagnosticLog.log("  buildModel: 4 managedObjectClassName set")

        let idAttr = NSAttributeDescription()
        DiagnosticLog.log("  buildModel: 5 idAttr created")
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false
        idAttr.defaultValue = UUID()
        DiagnosticLog.log("  buildModel: 6 idAttr configured")

        let nameAttr = NSAttributeDescription()
        nameAttr.name = "name"
        nameAttr.attributeType = .stringAttributeType
        nameAttr.isOptional = false
        nameAttr.defaultValue = ""
        DiagnosticLog.log("  buildModel: 7 nameAttr configured")

        let iconAttr = NSAttributeDescription()
        iconAttr.name = "iconName"
        iconAttr.attributeType = .stringAttributeType
        iconAttr.isOptional = false
        iconAttr.defaultValue = "house"
        DiagnosticLog.log("  buildModel: 8 iconAttr configured")

        let typeAttr = NSAttributeDescription()
        typeAttr.name = "typeRaw"
        typeAttr.attributeType = .stringAttributeType
        typeAttr.isOptional = false
        typeAttr.defaultValue = "personal"
        DiagnosticLog.log("  buildModel: 9 typeAttr configured")

        let currencyAttr = NSAttributeDescription()
        currencyAttr.name = "defaultCurrencyCode"
        currencyAttr.attributeType = .stringAttributeType
        currencyAttr.isOptional = false
        currencyAttr.defaultValue = "CNY"
        DiagnosticLog.log("  buildModel: 10 currencyAttr configured")

        let sharedAttr = NSAttributeDescription()
        sharedAttr.name = "isShared"
        sharedAttr.attributeType = .booleanAttributeType
        sharedAttr.isOptional = false
        sharedAttr.defaultValue = false
        DiagnosticLog.log("  buildModel: 11 sharedAttr configured")

        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false
        createdAtAttr.defaultValue = Date()
        DiagnosticLog.log("  buildModel: 12 createdAtAttr configured")

        let ownerAttr = NSAttributeDescription()
        ownerAttr.name = "ownerUserRecordID"
        ownerAttr.attributeType = .stringAttributeType
        ownerAttr.isOptional = true
        DiagnosticLog.log("  buildModel: 13 ownerAttr configured")

        ledgerEntity.properties = [idAttr, nameAttr, iconAttr, typeAttr, currencyAttr, sharedAttr, createdAtAttr, ownerAttr]
        DiagnosticLog.log("  buildModel: 14 properties set")

        model.entities = [ledgerEntity]
        DiagnosticLog.log("  buildModel: 14b entities set")
        model.setEntities([ledgerEntity], forConfigurationName: "default")
        DiagnosticLog.log("  buildModel: 15 default config set")
        model.setEntities([ledgerEntity], forConfigurationName: "Private")
        DiagnosticLog.log("  buildModel: 16 Private config set")
        model.setEntities([ledgerEntity], forConfigurationName: "Shared")
        DiagnosticLog.log("  buildModel: 17 Shared config set")

        DiagnosticLog.log("  buildModel: 18 done")
        return model
    }
}
