import Foundation
import SwiftData

@Model
final class Ledger {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "house"
    var typeRaw: String = LedgerType.personal.rawValue
    var defaultCurrencyCode: String = "CNY"
    var isShared: Bool = false
    var createdAt: Date = Date()
    var ownerUserRecordID: String?

    @Relationship(deleteRule: .cascade, inverse: \User.ledger)
    var members: [User]? = []

    @Relationship(deleteRule: .cascade, inverse: \Account.ledger)
    var accounts: [Account]? = []

    @Relationship(deleteRule: .cascade, inverse: \Category.ledger)
    var categories: [Category]? = []

    @Relationship(deleteRule: .cascade, inverse: \Transaction.ledger)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \TransactionTemplate.ledger)
    var templates: [TransactionTemplate]? = []

    @Relationship(deleteRule: .cascade, inverse: \BudgetBook.ledger)
    var budgetBooks: [BudgetBook]? = []

    @Relationship(deleteRule: .cascade, inverse: \CreditCardStatement.ledger)
    var creditCardStatements: [CreditCardStatement]? = []

    @Relationship(deleteRule: .cascade, inverse: \Member.ledger)
    var memberContacts: [Member]? = []

    @Relationship(deleteRule: .cascade, inverse: \Merchant.ledger)
    var merchants: [Merchant]? = []

    @Relationship(deleteRule: .cascade, inverse: \Project.ledger)
    var projects: [Project]? = []

    @Relationship(deleteRule: .cascade, inverse: \SplitGroup.ledger)
    var splitGroups: [SplitGroup]? = []

    var type: LedgerType {
        get { LedgerType(rawValue: typeRaw) ?? .personal }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "house",
        type: LedgerType = .personal,
        defaultCurrencyCode: String = "CNY",
        isShared: Bool = false,
        ownerUserRecordID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.typeRaw = type.rawValue
        self.defaultCurrencyCode = defaultCurrencyCode
        self.isShared = isShared
        self.createdAt = Date()
        self.ownerUserRecordID = ownerUserRecordID
    }
}
