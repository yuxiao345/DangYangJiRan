import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String?
    var startDate: Date?
    var endDate: Date?
    var budget: Decimal?
    var isActive: Bool = true
    var sortOrder: Int = 0

    var ledger: Ledger?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.project)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \TransactionTemplate.project)
    var templateTransactions: [TransactionTemplate]? = []

    init(
        id: UUID = UUID(),
        name: String,
        desc: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        budget: Decimal? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.desc = desc
        self.startDate = startDate
        self.endDate = endDate
        self.budget = budget
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}
