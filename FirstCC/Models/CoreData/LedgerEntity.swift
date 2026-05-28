import Foundation
@preconcurrency import CoreData

@objc(Ledger)
final class Ledger: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var iconName: String
    @NSManaged var typeRaw: String
    @NSManaged var defaultCurrencyCode: String
    @NSManaged var isShared: Bool
    @NSManaged var createdAt: Date
    @NSManaged var ownerUserRecordID: String?
    @NSManaged var shareRecordName: String?

    @NSManaged var members: Set<User>?
    @NSManaged var accounts: Set<Account>?
    @NSManaged var categories: Set<Category>?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var templates: Set<TransactionTemplate>?
    @NSManaged var budgetBooks: Set<BudgetBook>?
    @NSManaged var creditCardStatements: Set<CreditCardStatement>?
    @NSManaged var memberContacts: Set<Member>?
    @NSManaged var merchants: Set<Merchant>?
    @NSManaged var projects: Set<Project>?
    @NSManaged var splitGroups: Set<SplitGroup>?

    var type: LedgerType {
        get { LedgerType(rawValue: typeRaw) ?? .personal }
        set { typeRaw = newValue.rawValue }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date()
    }

    convenience init(
        name: String,
        iconName: String = "house",
        type: LedgerType = .personal,
        defaultCurrencyCode: String = "CNY",
        isShared: Bool = false,
        ownerUserRecordID: String? = nil,
        shareRecordName: String? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.iconName = iconName
        self.typeRaw = type.rawValue
        self.defaultCurrencyCode = defaultCurrencyCode
        self.isShared = isShared
        self.ownerUserRecordID = ownerUserRecordID
        self.shareRecordName = shareRecordName
    }
}

extension Ledger: Identifiable {}
