import Foundation
@preconcurrency import CoreData

@objc(TransactionTemplate)
final class TransactionTemplate: NSManagedObject, @unchecked Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var typeRaw: String
    @NSManaged var amountInFen: Int64
    @NSManaged var currencyCode: String
    @NSManaged var note: String?
    @NSManaged var tagsJSON: String
    @NSManaged var isRecurring: Bool
    @NSManaged var sortOrder: Int64
    @NSManaged var createdAt: Date

    @NSManaged var ledger: Ledger?
    @NSManaged var account: Account?
    @NSManaged var toAccount: Account?
    @NSManaged var category: Category?
    @NSManaged var member: Member?
    @NSManaged var merchant: Merchant?
    @NSManaged var project: Project?
    @NSManaged var generatedTransactions: Set<Transaction>?
    @NSManaged var recurringRule: RecurringRule?

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { Decimal(amountInFen) / 100 }
        set { amountInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }
    }

    var tags: [String] {
        get {
            guard let data = tagsJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            if let data = try? JSONEncoder().encode(newValue), let str = String(data: data, encoding: .utf8) {
                tagsJSON = str
            } else {
                tagsJSON = "[]"
            }
        }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
    }

    convenience init(
        name: String,
        type: TransactionType = .expense,
        amount: Decimal = 0,
        currencyCode: String = "CNY",
        note: String? = nil,
        tags: [String] = [],
        isRecurring: Bool = false,
        sortOrder: Int = 0,
        account: Account? = nil,
        toAccount: Account? = nil,
        category: Category? = nil,
        member: Member? = nil,
        merchant: Merchant? = nil,
        project: Project? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.typeRaw = type.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.note = note
        self.tags = tags
        self.isRecurring = isRecurring
        self.sortOrder = Int64(sortOrder)
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.member = member
        self.merchant = merchant
        self.project = project
    }
}

extension TransactionTemplate: Identifiable {}
