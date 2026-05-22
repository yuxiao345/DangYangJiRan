import SwiftUI
import SwiftData
import CloudKit
import CoreData
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare?
    let container: CKContainer
    let ledger: Ledger
    let isPresenting: Bool
    let syncService: SyncServiceImpl?
    let modelContainer: ModelContainer?

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
        Coordinator(ledger: ledger, container: container, syncService: syncService, modelContainer: modelContainer)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let ledger: Ledger
        let container: CKContainer
        let syncService: SyncServiceImpl?
        let modelContainer: ModelContainer?

        init(ledger: Ledger, container: CKContainer, syncService: SyncServiceImpl?, modelContainer: ModelContainer?) {
            self.ledger = ledger
            self.container = container
            self.syncService = syncService
            self.modelContainer = modelContainer
        }

        @MainActor
        func createShare() async throws -> CKShare {
            if let syncService {
                return try await syncService.createShare(for: ledger)
            }
            guard let modelContainer else {
                throw SyncError.invalidShareTarget
            }
            guard let moc = modelContainer.mainContext.coreDataContext,
                  let coordinator = moc.persistentStoreCoordinator as? NSPersistentCloudKitContainer else {
                throw SyncError.invalidShareTarget
            }

            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Ledger")
            fetch.predicate = NSPredicate(format: "id == %@", ledger.id as CVarArg)
            fetch.fetchLimit = 1
            guard let nsObject = try moc.fetch(fetch).first else {
                throw SyncError.invalidShareTarget
            }

            let (_, share, _) = try await coordinator.share([nsObject], to: nil)
            ledger.isShared = true
            return share
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            ledger.isShared = false
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            ledger.isShared = true
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
