import Foundation
@preconcurrency import CoreData

@objc(Account)
final class Account: NSManagedObject,  Sendable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var currencyCode: String
    @NSManaged var typeRaw: String
    @NSManaged var customTypeName: String?
    @NSManaged var iconName: String?
    @NSManaged var colorHex: String?
    @NSManaged var initialBalanceInFen: Int64
    @NSManaged var creditLimitInFen: Int64  // optional in model
    @NSManaged var billingDay: Int64  // optional, 0 = nil
    @NSManaged var dueDay: Int64      // optional, 0 = nil
    @NSManaged var isArchived: Bool
    @NSManaged var sortOrder: Int64
    @NSManaged var createdAt: Date

    @NSManaged var ledger: Ledger?
    @NSManaged var transactions: Set<Transaction>?
    @NSManaged var incomingTransactions: Set<Transaction>?
    @NSManaged var templates: Set<TransactionTemplate>?
    @NSManaged var incomingTemplates: Set<TransactionTemplate>?
    @NSManaged var creditCardStatements: Set<CreditCardStatement>?

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var typeDisplayName: String {
        if type == .other, let custom = customTypeName, !custom.isEmpty { return custom }
        return type.displayName
    }

    var initialBalance: Decimal {
        get { Decimal(initialBalanceInFen) / 100 }
        set { initialBalanceInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }
    }

    var creditLimit: Decimal? {
        get { creditLimitInFen == 0 ? nil : Decimal(creditLimitInFen) / 100 }
        set { creditLimitInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    var billingDayValue: Int? {
        get { billingDay == 0 ? nil : Int(billingDay) }
        set { billingDay = Int64(newValue ?? 0) }
    }

    var dueDayValue: Int? {
        get { dueDay == 0 ? nil : Int(dueDay) }
        set { dueDay = Int64(newValue ?? 0) }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
    }

    convenience init(
        name: String,
        currencyCode: String = "CNY",
        type: AccountType = .cash,
        iconName: String? = nil,
        colorHex: String? = nil,
        initialBalance: Decimal = 0,
        creditLimit: Decimal? = nil,
        billingDay: Int? = nil,
        dueDay: Int? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.name = name
        self.currencyCode = currencyCode
        self.typeRaw = type.rawValue
        self.iconName = iconName ?? type.systemIcon
        self.colorHex = colorHex
        self.initialBalance = initialBalance
        self.creditLimit = creditLimit
        self.billingDayValue = billingDay
        self.dueDayValue = dueDay
        self.isArchived = isArchived
        self.sortOrder = Int64(sortOrder)
    }
}

extension Account: Identifiable {}

extension Account {
    /// Returns the effective currency code, falling back to "CNY" if nil or empty.
    var effectiveCurrencyCode: String {
        let code = currencyCode
        return code.isEmpty ? "CNY" : code
    }
}
