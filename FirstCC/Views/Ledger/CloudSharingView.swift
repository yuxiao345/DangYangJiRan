import SwiftUI
@preconcurrency import CoreData
import CloudKit
@preconcurrency import CoreData
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare?
    let container: CKContainer
    let ledger: Ledger
    let isPresenting: Bool
    let syncService: SyncServiceImpl?
    let coreDataStack: CoreDataStack?
    var onStopSharing: (() -> Void)?

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller: UICloudSharingController
        if let share = share {
            controller = UICloudSharingController(share: share, container: container)
        } else {
            controller = UICloudSharingController { controller, prepareCompletionHandler in
                Task { @MainActor in
                    do {
                        let share = try await context.coordinator.createShare()
                        prepareCompletionHandler(share, container, nil)
                    } catch {
                        prepareCompletionHandler(nil, container, error)
                    }
                }
            }
        }

        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(ledger: ledger, container: container, syncService: syncService, coreDataStack: coreDataStack, onStopSharing: onStopSharing)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let ledger: Ledger
        let container: CKContainer
        let syncService: SyncServiceImpl?
        let coreDataStack: CoreDataStack?
        let onStopSharing: (() -> Void)?

        init(ledger: Ledger, container: CKContainer, syncService: SyncServiceImpl?, coreDataStack: CoreDataStack?, onStopSharing: (() -> Void)?) {
            self.ledger = ledger
            self.container = container
            self.syncService = syncService
            self.coreDataStack = coreDataStack
            self.onStopSharing = onStopSharing
        }

        @MainActor
        func createShare() async throws -> CKShare {
            if let syncService {
                return try await syncService.createShare(for: ledger)
            }
            guard let coreDataStack else {
                throw SyncError.invalidShareTarget
            }
            let container = coreDataStack.container
            let moc = container.viewContext
            guard (moc.persistentStoreCoordinator as? NSPersistentCloudKitContainer) != nil else {
                throw SyncError.invalidShareTarget
            }

            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
            fetch.predicate = NSPredicate(format: "id == %@", ledger.id as CVarArg)
            fetch.fetchLimit = 1
            guard let nsObject = try moc.fetch(fetch).first else {
                throw SyncError.invalidShareTarget
            }

            let (_, share, _) = try await container.share([nsObject], to: nil)
            ledger.isShared = true
            ledger.shareRecordName = share.recordID.recordName
            return share
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            ledger.isShared = false
            onStopSharing?()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            ledger.isShared = true
            // Re-sync participants after owner adds/removes people
            if let share = csc.share, let syncService {
                Task {
                    try? await syncService.syncParticipants(share: share, for: ledger)
                }
            }
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Logger.error("Failed to save share: \(error)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            ledger.name
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            nil
        }
    }
}
