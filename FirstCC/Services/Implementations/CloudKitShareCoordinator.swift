import Foundation
import CoreData
import CloudKit

final class CloudKitShareCoordinator {
    static let shared = CloudKitShareCoordinator()

    private let initQueue = DispatchQueue(label: "com.qianey.share-coordinator")
    private var persistence: SharedPersistenceController?

    private init() {
        DiagnosticLog.log("CloudKitCoordinator: init")
    }

    @MainActor
    private func getPersistence() async throws -> SharedPersistenceController {
        if let p = persistence { return p }
        DiagnosticLog.log("CloudKitCoordinator: creating SharedPersistenceController (async)")
        let controller = try await SharedPersistenceController.create()
        persistence = controller
        DiagnosticLog.log("CloudKitCoordinator: SharedPersistenceController ready")
        return controller
    }

    @MainActor
    func createShare(ledgerID: UUID, name: String) async throws -> CKShare {
        DiagnosticLog.log("CloudKitCoordinator.createShare: begin")
        let p = try await getPersistence()
        DiagnosticLog.log("CloudKitCoordinator.createShare: got persistence")
        let share = try await p.createShareForLedger(id: ledgerID, name: name)
        DiagnosticLog.log("CloudKitCoordinator.createShare: success recordID=\(share.recordID)")
        return share
    }

    @MainActor
    func accept(_ metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("CloudKitCoordinator.accept: begin")
        let p = try await getPersistence()
        DiagnosticLog.log("CloudKitCoordinator.accept: got persistence")
        try await p.acceptShareInvitations(from: metadata)
        DiagnosticLog.log("CloudKitCoordinator.accept: acceptShareInvitations succeeded")
    }

    func pollForLedgers() async throws -> Bool {
        DiagnosticLog.log("CloudKitCoordinator.pollForLedgers: begin")
        let p = try await getPersistence()
        let countExists = try p.fetchSharedLedgerCount() > 0
        DiagnosticLog.log("CloudKitCoordinator.pollForLedgers: hasData=\(countExists)")
        return countExists
    }

    func containerForImport() async throws -> NSPersistentCloudKitContainer {
        DiagnosticLog.log("CloudKitCoordinator.containerForImport: begin")
        let p = try await getPersistence()
        return p.container
    }

    func sharedStoreForImport() async throws -> NSPersistentStore {
        DiagnosticLog.log("CloudKitCoordinator.sharedStoreForImport: begin")
        let p = try await getPersistence()
        return p.sharedStore
    }
}
