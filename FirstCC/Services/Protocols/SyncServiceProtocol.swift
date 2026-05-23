import Foundation
import CloudKit
import SwiftData

protocol SyncServiceProtocol {
    var status: SyncStatus { get }
    func startSync() async throws
    func createShare(for ledger: Ledger) async throws -> CKShare
    func acceptShare(metadata: CKShare.Metadata) async throws
    func importSharedData(into modelContainer: ModelContainer) async throws -> [Ledger]
    func fetchParticipants(for ledger: Ledger) async throws -> [CKShare.Participant]
    func removeParticipant(_ participant: CKShare.Participant, from ledger: Ledger) async throws
    func syncNow() async throws
}
