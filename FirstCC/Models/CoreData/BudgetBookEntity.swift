import Foundation
@preconcurrency import CoreData

@objc(BudgetBook)
final class BudgetBook: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var startDate: Date
    @NSManaged var endDate: Date
    @NSManaged var isActive: Bool
    @NSManaged var sortOrder: Int64
    @NSManaged var createdAt: Date
    @NSManaged var matchBudgetItems: Bool

    @NSManaged var items: Set<BudgetItem>?
    @NSManaged var ledger: Ledger?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
        matchBudgetItems = false
        startDate = Date.now
        endDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? Date()
    }

    convenience init(
        name: String = "",
        startDate: Date = Date.now,
        endDate: Date? = nil,
        isActive: Bool = true,
        matchBudgetItems: Bool = false,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.startDate = startDate
        self.endDate = endDate ?? (Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? Date())
        self.isActive = isActive
        self.matchBudgetItems = matchBudgetItems
    }
}

extension BudgetBook: Identifiable {}
