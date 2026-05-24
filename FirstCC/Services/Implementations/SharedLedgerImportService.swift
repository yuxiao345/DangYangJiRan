import Foundation
@preconcurrency import CoreData

@MainActor
final class SharedLedgerImportService {
    static let shared = SharedLedgerImportService()

    private init() {}

    func importSharedLedgers(
        from container: NSPersistentCloudKitContainer,
        sharedStore: NSPersistentStore,
        into viewContext: NSManagedObjectContext
    ) throws -> [Ledger] {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
        fetch.affectedStores = [sharedStore]
        let sharedObjects = try container.viewContext.fetch(fetch)
        DiagnosticLog.log("ImportService: fetched \(sharedObjects.count) ledger(s) from shared store")
        for (index, object) in sharedObjects.enumerated() {
            let id = (object.value(forKey: "id") as? UUID)?.uuidString ?? "nil"
            let name = object.value(forKey: "name") as? String ?? "nil"
            DiagnosticLog.log("ImportService: [\(index)] id=\(id) name=\(name)")
        }

        let existingFetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        let existingLedgers = try viewContext.fetch(existingFetch)
        var existingByID = Dictionary(uniqueKeysWithValues: existingLedgers.map { ($0.id, $0) })
        var imported: [Ledger] = []

        for object in sharedObjects {
            guard let id = object.value(forKey: "id") as? UUID else {
                DiagnosticLog.log("ImportService: object missing UUID, skip")
                continue
            }

            let name = object.value(forKey: "name") as? String ?? "共享账本"
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
                existing.typeRaw = typeRaw
                existing.defaultCurrencyCode = currencyCode
                existing.isShared = true
                existing.ownerUserRecordID = ownerUserRecordID
                ledger = existing
            } else {
                DiagnosticLog.log("ImportService: creating new \(name)")
                ledger = Ledger(
                    name: name,
                    iconName: iconName,
                    type: type,
                    defaultCurrencyCode: currencyCode,
                    isShared: true,
                    ownerUserRecordID: ownerUserRecordID,
                    context: viewContext
                )
                existingByID[id] = ledger
            }
            imported.append(ledger)
        }

        if viewContext.hasChanges {
            try viewContext.save()
            DiagnosticLog.log("ImportService: saved \(imported.count) ledger(s)")
        }

        return imported
    }
}
