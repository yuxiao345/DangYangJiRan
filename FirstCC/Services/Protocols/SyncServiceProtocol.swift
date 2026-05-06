import Foundation
import CloudKit

protocol SyncServiceProtocol {
    var status: SyncStatus { get }
    func startSync() async throws
    func createShare(for ledger: Ledger) async throws -> CKShare
    func acceptShare(url: URL) async throws
    func fetchParticipants(for ledger: Ledger) async throws -> [CKShare.Participant]
    func removeParticipant(_ participant: CKShare.Participant, from ledger: Ledger) async throws
    func syncNow() async throws
}
