import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var displayName: String = ""
    var cloudKitUserRecordID: String = ""
    var roleRaw: String = LedgerRole.member.rawValue
    var joinedAt: Date = Date()

    var ledger: Ledger?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.createdBy)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \SplitEntry.user)
    var splitEntries: [SplitEntry]? = []

    var role: LedgerRole {
        get { LedgerRole(rawValue: roleRaw) ?? .member }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        cloudKitUserRecordID: String,
        role: LedgerRole = .member
    ) {
        self.id = id
        self.displayName = displayName
        self.cloudKitUserRecordID = cloudKitUserRecordID
        self.roleRaw = role.rawValue
        self.joinedAt = Date()
    }
}
