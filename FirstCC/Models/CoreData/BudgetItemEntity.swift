import Foundation
@preconcurrency import CoreData

@objc(BudgetItem)
final class BudgetItem: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var amountInFen: Int64
    @NSManaged var periodRaw: String
    @NSManaged var alertThreshold: Double
    @NSManaged var isActive: Bool

    @NSManaged var book: BudgetBook?
    @NSManaged var category: Category?

    var amount: Decimal {
        get { Decimal(amountInFen) / 100 }
        set { amountInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .monthly }
        set { periodRaw = newValue.rawValue }
    }

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

    var totalBudget: Decimal {
        NSDecimalNumber(value: periodCount).decimalValue * amount
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        amount: Decimal = 0,
        period: BudgetPeriod = .monthly,
        alertThreshold: Double = 0.8,
        isActive: Bool = true,
        category: Category? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.amount = amount
        self.periodRaw = period.rawValue
        self.alertThreshold = alertThreshold
        self.isActive = isActive
        self.category = category
    }
}

extension BudgetItem: Identifiable {}
