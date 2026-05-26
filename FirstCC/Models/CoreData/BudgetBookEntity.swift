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

    @NSManaged var items: Set<BudgetItem>?
    @NSManaged var ledger: Ledger?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
        startDate = Date()
        endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    convenience init(
        name: String = "",
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.startDate = startDate
        self.endDate = endDate ?? (Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        self.isActive = isActive
    }
}

extension BudgetBook: Identifiable {}
