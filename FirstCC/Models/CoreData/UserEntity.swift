import Foundation
@preconcurrency import CoreData

@objc(User)
final class User: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var displayName: String
    @NSManaged var cloudKitUserRecordID: String
    @NSManaged var roleRaw: String
    @NSManaged var joinedAt: Date

    @NSManaged var ledger: Ledger?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var splitEntries: Set<SplitEntry>?

    var role: LedgerRole {
        get { LedgerRole(rawValue: roleRaw) ?? .member }
        set { roleRaw = newValue.rawValue }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        joinedAt = Date.now
    }

    convenience init(
        displayName: String,
        cloudKitUserRecordID: String,
        role: LedgerRole = .member,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.displayName = displayName
        self.cloudKitUserRecordID = cloudKitUserRecordID
        self.roleRaw = role.rawValue
    }
}

extension User: Identifiable {}
