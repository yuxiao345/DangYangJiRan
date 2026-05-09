import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID
    var name: String
    var currencyCode: String
    var typeRaw: String
    var iconName: String?
    var colorHex: String?
    var customIconData: Data?
    var initialBalance: Decimal
    var creditLimit: Decimal?
    var billDate: Date?
    var dueDate: Date?
    var billingDay: Int?
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date

    var ledger: Ledger?

    @Relationship(deleteRule: .nullify)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade)
    var installmentPlans: [InstallmentPlan]? = []

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        currencyCode: String = "CNY",
        type: AccountType = .cash,
        iconName: String? = nil,
        colorHex: String? = nil,
        customIconData: Data? = nil,
        initialBalance: Decimal = 0,
        creditLimit: Decimal? = nil,
        billDate: Date? = nil,
        dueDate: Date? = nil,
        billingDay: Int? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.typeRaw = type.rawValue
        self.iconName = iconName ?? type.systemIcon
        self.colorHex = colorHex
        self.customIconData = customIconData
        self.initialBalance = initialBalance
        self.creditLimit = creditLimit
        self.billDate = billDate
        self.dueDate = dueDate
        self.billingDay = billingDay
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
