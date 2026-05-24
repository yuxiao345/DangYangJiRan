import Foundation
@preconcurrency import CoreData

@objc(Member)
final class Member: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var avatar: String
    @NSManaged var isActive: Bool
    @NSManaged var sortOrder: Int64

    @NSManaged var ledger: Ledger?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var templateTransactions: Set<TransactionTemplate>?
    @NSManaged var splitEntries: Set<SplitEntry>?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }

    convenience init(
        name: String,
        avatar: String = "person.circle",
        isActive: Bool = true,
        sortOrder: Int = 0,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.avatar = avatar
        self.isActive = isActive
        self.sortOrder = Int64(sortOrder)
    }
}

extension Member: Identifiable {}
