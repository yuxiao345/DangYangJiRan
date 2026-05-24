import Foundation
@preconcurrency import CoreData

@objc(Merchant)
final class Merchant: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var category: String?
    @NSManaged var isActive: Bool
    @NSManaged var sortOrder: Int64

    @NSManaged var ledger: Ledger?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var templateTransactions: Set<TransactionTemplate>?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        name: String,
        category: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.category = category
        self.isActive = isActive
        self.sortOrder = Int64(sortOrder)
    }
}

extension Merchant: Identifiable {}
