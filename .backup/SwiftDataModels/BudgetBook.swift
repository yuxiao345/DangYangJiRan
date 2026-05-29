import Foundation
import SwiftData

@Model
final class BudgetBook {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date = Date()
    var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var isActive: Bool = true
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \BudgetItem.book)
    var items: [BudgetItem]? = []

    var ledger: Ledger?

    init(
        id: UUID = UUID(),
        name: String = "",
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate ?? (Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
