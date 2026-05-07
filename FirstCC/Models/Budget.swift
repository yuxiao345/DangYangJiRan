import Foundation
import SwiftData

@Model
final class BudgetItem {
    var id: UUID
    var amount: Decimal
    var periodRaw: String
    var alertThreshold: Double
    var isActive: Bool

    var book: BudgetBook?
    var category: Category?

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

    /// Number of periods within the book's date range (e.g., 12 months, 4 quarters)
    var periodCount: Double {
        guard let book = book else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: book.startDate, to: book.endDate).day ?? 0
        let totalDays = Double(max(days, 1))
        switch period {
        case .weekly:
            return (totalDays / 7.0).rounded()
        case .monthly:
            return (totalDays / (365.25 / 12.0)).rounded()
        case .quarterly:
            let months = totalDays / (365.25 / 12.0)
            let quarters = months / 3.0
            return (quarters * 10).rounded() / 10.0
        case .yearly:
            let years = totalDays / 365.25
            return (years * 10).rounded() / 10.0
        }
    }

    /// Total budget for the entire book duration
    var totalBudget: Decimal {
        Decimal(periodCount) * amount
    }

    init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        period: BudgetPeriod = .monthly,
        alertThreshold: Double = 0.8,
        isActive: Bool = true,
        category: Category? = nil
    ) {
        self.id = id
        self.amount = amount
        self.periodRaw = period.rawValue
        self.alertThreshold = alertThreshold
        self.isActive = isActive
        self.category = category
    }
}
