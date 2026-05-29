import Foundation
import SwiftUI
@preconcurrency import CoreData
import CloudKit

enum CloudKitConfig {
    static let containerIdentifier = "iCloud.com.qianey"
    static let sharedScope = CKDatabase.Scope.shared
    static let privateScope = CKDatabase.Scope.private

    static let ledgerRecordType = "Ledger"
    static let transactionRecordType = "Transaction"
    static let accountRecordType = "Account"
    static let categoryRecordType = "Category"
}

// MARK: - LedgerTransferable (CKShareTransferRepresentation)

/// Transferable wrapper for CKShare via ShareLink (iOS 26+).
/// Replaces the deprecated UICloudSharingController(preparationHandler:) flow.
struct LedgerTransferable: Transferable {
    let ledgerID: UUID
    let ledgerName: String
    let coreDataStack: CoreDataStack

    @MainActor
    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let container = CKContainer(identifier: CloudKitConfig.containerIdentifier)

            let fetch = NSFetchRequest<Ledger>(entityName: "Ledger")
            fetch.predicate = NSPredicate(format: "id == %@", item.ledgerID as CVarArg)
            fetch.fetchLimit = 1

            if let existing = try? item.coreDataStack.container.viewContext.fetch(fetch).first,
               let shares = try? item.coreDataStack.container.fetchShares(matching: [existing.objectID]),
               let (_, share) = shares.first {
                return .existing(share, container: container)
            }

            return .prepareShare(container: container) {
                let share = try await item.coreDataStack.createShareForLedger(
                    id: item.ledgerID,
                    name: item.ledgerName
                )
                await MainActor.run {
                    if let existing = try? item.coreDataStack.container.viewContext.fetch(fetch).first {
                        existing.isShared = true
                        existing.shareRecordName = share.recordID.recordName
                        try? item.coreDataStack.container.viewContext.save()
                    }
                }
                NotificationCenter.default.post(
                    name: .ledgerShareCreated,
                    object: nil,
                    userInfo: ["ledgerID": item.ledgerID]
                )
                return share
            }
        }
    }
}

extension Notification.Name {
    static let ledgerShareCreated = Notification.Name("ledgerShareCreated")
}
