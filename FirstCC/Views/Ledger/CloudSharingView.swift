import SwiftUI
import CloudKit
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare?
    let container: CKContainer
    let ledger: Ledger
    let isPresenting: Bool

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller: UICloudSharingController
        if let share = share {
            controller = UICloudSharingController(share: share, container: container)
        } else {
            controller = UICloudSharingController { controller, prepareCompletionHandler in
                Task {
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
        Coordinator(ledger: ledger, container: container)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let ledger: Ledger
        let container: CKContainer

        init(ledger: Ledger, container: CKContainer) {
            self.ledger = ledger
            self.container = container
        }

        func createShare() async throws -> CKShare {
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )
            let recordID = CKRecord.ID(recordName: ledger.id.uuidString, zoneID: zoneID)
            let share = CKShare(rootRecord: CKRecord(recordType: "Ledger", recordID: recordID))
            share.publicPermission = .readWrite

            try await container.sharedCloudDatabase.save(share)
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
