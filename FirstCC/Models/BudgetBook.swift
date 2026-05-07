import Foundation
import SwiftData

@Model
final class BudgetBook {
    var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var isActive: Bool
    var createdAt: Date

    var items: [BudgetItem]? = []

    var ledger: Ledger?

    init(
        id: UUID = UUID(),
        name: String = "",
        startDate: Date = Date(),
        endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
