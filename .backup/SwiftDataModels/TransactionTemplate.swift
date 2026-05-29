import Foundation
import SwiftData

@Model
final class TransactionTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = TransactionType.expense.rawValue
    var amount: Decimal = 0
    var currencyCode: String = "CNY"
    var note: String?
    var tags: [String] = []
    var isRecurring: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var ledger: Ledger?

    var account: Account?

    var toAccount: Account?

    var category: Category?

    var member: Member?

    var merchant: Merchant?

    var project: Project?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.template)
    var generatedTransactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \RecurringRule.template)
    var recurringRule: RecurringRule?

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
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
        project: Project? = nil
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.note = note
        self.tags = tags
        self.isRecurring = isRecurring
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.member = member
        self.merchant = merchant
        self.project = project
    }
}
