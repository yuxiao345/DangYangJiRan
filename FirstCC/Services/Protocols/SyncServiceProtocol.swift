import Foundation
import CloudKit

protocol SyncServiceProtocol {
    var status: SyncStatus { get }
    func startSync() async throws
    func createShare(for ledger: Ledger) async throws -> CKShare
    func acceptShare(metadata: CKShare.Metadata) async throws
    func importSharedData(into stack: CoreDataStack) async throws -> [Ledger]
    func fetchParticipants(for ledger: Ledger) async throws -> [CKShare.Participant]
    func syncParticipants(metadata: CKShare.Metadata, for ledger: Ledger) async throws
    func removeParticipant(_ participant: CKShare.Participant, from ledger: Ledger) async throws
    func syncNow() async throws
}
