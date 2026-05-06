import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var amount: Decimal
    var periodRaw: String
    var startDate: Date
    var alertThreshold: Double
    var isActive: Bool

    var ledger: Ledger?

    var category: Category?

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        period: BudgetPeriod = .monthly,
        startDate: Date = Date(),
        alertThreshold: Double = 0.8,
        isActive: Bool = true,
        category: Category? = nil
    ) {
        self.id = id
        self.amount = amount
        self.periodRaw = period.rawValue
        self.startDate = startDate
        self.alertThreshold = alertThreshold
        self.isActive = isActive
        self.category = category
    }
}
