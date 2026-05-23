import Foundation
import CoreData
import SwiftData

@MainActor
final class SharedLedgerImportService {
    static let shared = SharedLedgerImportService()

    private init() {}

    func importSharedLedgers(
        from container: NSPersistentCloudKitContainer,
        sharedStore: NSPersistentStore,
        into modelContainer: ModelContainer
    ) throws -> [Ledger] {
        let viewContext = container.viewContext
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
        fetch.affectedStores = [sharedStore]
        let sharedObjects = try viewContext.fetch(fetch)
        DiagnosticLog.log("ImportService: fetched \(sharedObjects.count) ledger(s) from shared store")
        for (index, object) in sharedObjects.enumerated() {
            let objectID = object.objectID.uriRepresentation().absoluteString
            let id = (object.value(forKey: "id") as? UUID)?.uuidString ?? "nil"
            let name = object.value(forKey: "name") as? String ?? "nil"
            DiagnosticLog.log("ImportService: [\(index)] objectID=\(objectID) id=\(id) name=\(name)")
        }
        Logger.info("SharedLedgerImportService fetched \(sharedObjects.count) ledger object(s) from shared Core Data stack")

        let modelContext = modelContainer.mainContext
        let existingLedgers = try modelContext.fetch(FetchDescriptor<Ledger>())
        var existingByID = Dictionary(uniqueKeysWithValues: existingLedgers.map { ($0.id, $0) })
        var imported: [Ledger] = []

        for object in sharedObjects {
            guard let id = object.value(forKey: "id") as? UUID else {
                DiagnosticLog.log("ImportService: object missing UUID, skip")
                Logger.info("Shared ledger object missing UUID, skipping")
                continue
            }

            let name = object.value(forKey: "name") as? String ?? "共享账本"
            DiagnosticLog.log("ImportService: processing \(name) (\(id.uuidString.prefix(8)))")
            Logger.info("Importing shared ledger candidate: \(name), id=\(id.uuidString)")

            let iconName = object.value(forKey: "iconName") as? String ?? "person.2"
            let typeRaw = object.value(forKey: "typeRaw") as? String ?? LedgerType.personal.rawValue
            let currencyCode = object.value(forKey: "defaultCurrencyCode") as? String ?? "CNY"
            let ownerUserRecordID = object.value(forKey: "ownerUserRecordID") as? String
            let type = LedgerType(rawValue: typeRaw) ?? .personal

            let ledger: Ledger
            if let existing = existingByID[id] {
                DiagnosticLog.log("ImportService: updating existing \(name)")
                existing.name = name
                existing.iconName = iconName
                existing.type = type
                existing.defaultCurrencyCode = currencyCode
                existing.isShared = true
                existing.ownerUserRecordID = ownerUserRecordID
                ledger = existing
            } else {
                DiagnosticLog.log("ImportService: creating new \(name)")
                let created = Ledger(
                    id: id,
                    name: name,
                    iconName: iconName,
                    type: type,
                    defaultCurrencyCode: currencyCode,
                    isShared: true,
                    ownerUserRecordID: ownerUserRecordID
                )
                modelContext.insert(created)
                existingByID[id] = created
                ledger = created
            }
            imported.append(ledger)
        }

        if modelContext.hasChanges {
            try modelContext.save()
            DiagnosticLog.log("ImportService: saved \(imported.count) ledger(s) to SwiftData")
            Logger.info("Saved imported shared ledgers into SwiftData main stack")
        } else {
            DiagnosticLog.log("ImportService: no changes to save")
            Logger.info("No SwiftData changes when importing shared ledgers")
        }

        Logger.info("SharedLedgerImportService returning \(imported.count) imported ledger(s)")
        return imported
    }
}
