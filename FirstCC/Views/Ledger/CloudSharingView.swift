import SwiftUI
@preconcurrency import CoreData
import CloudKit
import UIKit

/// Wraps UICloudSharingController for managing an existing CKShare.
/// Share creation: Button → createShareAndShow() → this view.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let ledger: Ledger
    let syncService: SyncServiceImpl?
    var onStopSharing: (() -> Void)?

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(ledger: ledger, syncService: syncService, onStopSharing: onStopSharing)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let ledger: Ledger
        let syncService: SyncServiceImpl?
        let onStopSharing: (() -> Void)?

        init(ledger: Ledger, syncService: SyncServiceImpl?, onStopSharing: (() -> Void)?) {
            self.ledger = ledger
            self.syncService = syncService
            self.onStopSharing = onStopSharing
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                self.ledger.isShared = false
                self.onStopSharing?()
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
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
