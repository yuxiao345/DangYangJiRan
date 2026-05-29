import Foundation
@preconcurrency import CoreData
import CloudKit

final class CloudKitShareCoordinator {
    static let shared = CloudKitShareCoordinator()

    private var stack: CoreDataStack?

    private init() {
        DiagnosticLog.log("CloudKitCoordinator: init")
    }

    @MainActor
    private func getStack() async throws -> CoreDataStack {
        if let s = stack { return s }
        if let s = CoreDataStack.shared {
            stack = s
            DiagnosticLog.log("CloudKitCoordinator: using existing CoreDataStack")
            return s
        }
        fatalError("CloudKitCoordinator: CoreDataStack.shared not initialized")
    }

    @MainActor
    func createShare(ledgerID: UUID, name: String) async throws -> CKShare {
        DiagnosticLog.log("CloudKitCoordinator.createShare: begin")
        let s = try await getStack()
        let share = try await s.createShareForLedger(id: ledgerID, name: name)
        DiagnosticLog.log("CloudKitCoordinator.createShare: success recordID=\(share.recordID)")
        return share
    }

    @MainActor
    func accept(_ metadata: CKShare.Metadata) async throws {
        DiagnosticLog.log("CloudKitCoordinator.accept: begin")
        let s = try await getStack()
        try await s.acceptShareInvitations(from: metadata)
        DiagnosticLog.log("CloudKitCoordinator.accept: acceptShareInvitations succeeded")
    }

    @MainActor
    func pollForLedgers() async throws -> Bool {
        DiagnosticLog.log("CloudKitCoordinator.pollForLedgers: begin")
        let s = try await getStack()
        let countExists = try s.fetchSharedLedgerCount() > 0
        DiagnosticLog.log("CloudKitCoordinator.pollForLedgers: hasData=\(countExists)")
        return countExists
    }

    @MainActor
    func pollForLedgersOnlyCount() async throws -> Int {
        let s = try await getStack()
        return try s.fetchSharedLedgerCount()
    }

    @MainActor
    func containerForImport() async throws -> NSPersistentCloudKitContainer {
        DiagnosticLog.log("CloudKitCoordinator.containerForImport: begin")
        let s = try await getStack()
        return s.container
    }

    @MainActor
    func sharedStoreForImport() async throws -> NSPersistentStore {
        DiagnosticLog.log("CloudKitCoordinator.sharedStoreForImport: begin")
        let s = try await getStack()
        guard let store = s.sharedStore else {
            throw NSError(domain: "CloudKitShareCoordinator", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Shared store not ready"])
        }
        return store
    }
}
