import Foundation
@preconcurrency import CoreData

@objc(Project)
final class Project: NSManagedObject, @unchecked Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var desc: String?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var budgetInFen: Int64  // optional, 0 = nil
    @NSManaged var isActive: Bool
    @NSManaged var sortOrder: Int64

    @NSManaged var ledger: Ledger?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var templateTransactions: Set<TransactionTemplate>?

    var budget: Decimal? {
        get { budgetInFen == 0 ? nil : Decimal(budgetInFen) / 100 }
        set { budgetInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        name: String,
        desc: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        budget: Decimal? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.desc = desc
        self.startDate = startDate
        self.endDate = endDate
        self.budget = budget
        self.isActive = isActive
        self.sortOrder = Int64(sortOrder)
    }
}

extension Project: Identifiable {}
