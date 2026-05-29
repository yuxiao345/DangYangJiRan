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
        // Dump full inventory of shared store using COUNT queries.
        // COUNT does NOT load objects or fire relationship faults — it's a safe
        // SQL-level operation that won't cache empty results prematurely.
        dumpSharedStoreInventory(container: container, sharedStore: sharedStore)

        let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
        fetch.affectedStores = [sharedStore]
        let sharedLedgers = try container.viewContext.fetch(fetch)
        DiagnosticLog.log("ImportService: fetched \(sharedLedgers.count) ledger(s) from shared store")

        for ledger in sharedLedgers {
            DiagnosticLog.log("ImportService: ledger id=\(ledger.id.uuidString.prefix(8)) name=\(ledger.name)")
            var changed = false
            if !ledger.isShared {
                ledger.isShared = true
                changed = true
            }
            if changed {
                DiagnosticLog.log("ImportService: updated \(ledger.name)")
            }
        }

        if container.viewContext.hasChanges {
            try container.viewContext.save()
            DiagnosticLog.log("ImportService: saved")
        }

        return sharedLedgers
    }

    /// Count every entity type in the shared store using COUNT queries.
    /// Unlike accessing relationship properties, COUNT never fires a CoreData fault
    /// and therefore never caches an empty result before CloudKit has finished syncing.
    private func dumpSharedStoreInventory(
        container: NSPersistentCloudKitContainer,
        sharedStore: NSPersistentStore
    ) {
        let model = container.managedObjectModel

        DiagnosticLog.log("ImportService: --- shared store inventory (COUNT, no faults) ---")
        let context = container.viewContext

        for entity in model.entities {
            guard let name = entity.name else { continue }
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            fetch.affectedStores = [sharedStore]
            let count = (try? context.count(for: fetch)) ?? -1
            if count > 0 {
                DiagnosticLog.log("ImportService:   \(name) = \(count)")
            }
        }
        DiagnosticLog.log("ImportService: --- end inventory ---")
    }
}
