import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID
    var typeRaw: String
    var amount: Decimal
    var currencyCode: String
    var exchangeRate: Decimal?
    var convertedAmount: Decimal?
    var note: String?
    var date: Date
    var createdAt: Date
    var modifiedAt: Date
    var isReconciled: Bool
    var transferGroupId: UUID?
    var refundGroupId: UUID?
    var refundAmount: Decimal?
    var counterparty: String?
    var tags: [String]
    var photoURLs: [String]?
    var installmentPlanId: UUID?

    var ledger: Ledger?

    var account: Account?

    var toAccount: Account?

    var category: Category?

    var createdBy: User?

    var template: TransactionTemplate?

    var splitGroup: SplitGroup?

    var member: Member?

    var merchant: Merchant?

    var project: Project?

    @Relationship(deleteRule: .nullify)
    var sourceOfTransfer: Transaction? = nil

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        type: TransactionType = .expense,
        amount: Decimal = 0,
        currencyCode: String = "CNY",
        exchangeRate: Decimal? = nil,
        convertedAmount: Decimal? = nil,
        note: String? = nil,
        date: Date = Date(),
        isReconciled: Bool = false,
        transferGroupId: UUID? = nil,
        refundGroupId: UUID? = nil,
        refundAmount: Decimal? = nil,
        counterparty: String? = nil,
        tags: [String] = [],
        photoURLs: [String]? = nil,
        installmentPlanId: UUID? = nil,
        account: Account? = nil,
        toAccount: Account? = nil,
        category: Category? = nil,
        member: Member? = nil,
        merchant: Merchant? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.exchangeRate = exchangeRate
        self.convertedAmount = convertedAmount
        self.note = note
        self.date = date
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isReconciled = isReconciled
        self.transferGroupId = transferGroupId
        self.refundGroupId = refundGroupId
        self.refundAmount = refundAmount
        self.counterparty = counterparty
        self.tags = tags
        self.photoURLs = photoURLs
        self.installmentPlanId = installmentPlanId
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.member = member
        self.merchant = merchant
        self.project = project
    }
}
