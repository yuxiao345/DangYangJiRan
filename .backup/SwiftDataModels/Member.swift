import Foundation
import SwiftData

@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""
    var avatar: String = "person.circle"
    var isActive: Bool = true
    var sortOrder: Int = 0

    var ledger: Ledger?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.member)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \TransactionTemplate.member)
    var templateTransactions: [TransactionTemplate]? = []

    @Relationship(deleteRule: .nullify, inverse: \SplitEntry.member)
    var splitEntries: [SplitEntry]? = []

    init(id: UUID = UUID(), name: String, avatar: String = "person.circle", isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}
