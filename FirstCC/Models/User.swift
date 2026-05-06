import Foundation
import SwiftData

@Model
final class User {
    var id: UUID
    var displayName: String
    var cloudKitUserRecordID: String
    var roleRaw: String
    var joinedAt: Date

    var ledger: Ledger?

    @Relationship(deleteRule: .nullify)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade)
    var splitEntries: [SplitEntry]? = []

    @Relationship(deleteRule: .nullify)
    var lendings: [Lending]? = []

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
