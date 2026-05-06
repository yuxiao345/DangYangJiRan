import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var desc: String?
    var startDate: Date?
    var endDate: Date?
    var budget: Decimal?
    var isActive: Bool
    var sortOrder: Int

    var ledger: Ledger?

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
