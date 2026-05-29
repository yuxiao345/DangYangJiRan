import Foundation
import SwiftData

@Model
final class Merchant {
    var id: UUID = UUID()
    var name: String = ""
    var category: String?
    var isActive: Bool = true
    var sortOrder: Int = 0

    var ledger: Ledger?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.merchant)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \TransactionTemplate.merchant)
    var templateTransactions: [TransactionTemplate]? = []

    init(id: UUID = UUID(), name: String, category: String? = nil, isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.category = category
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}
