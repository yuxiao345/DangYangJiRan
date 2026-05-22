import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID = UUID()
    var typeRaw: String = TransactionType.expense.rawValue
    var amount: Decimal = 0
    var currencyCode: String = "CNY"
    var exchangeRate: Decimal?
    var convertedAmount: Decimal?
    var note: String?
    var date: Date = Date()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isReconciled: Bool = false
    var transferGroupId: UUID?
    var refundGroupId: UUID?
    var refundAmount: Decimal?
    var reimbursementStatusRaw: String = ReimbursementStatus.none.rawValue
    var reimbursedById: UUID?
    var lendingDirectionRaw: String?
    var lendingStatusRaw: String = LendingStatus.none.rawValue
    var settledByLendingTransactionId: UUID?
    var settledAmount: Decimal?
    var tags: [String] = []
    var photoURLs: [String]?
    var isSplitParent: Bool = false

    var ledger: Ledger?

    var account: Account?

    var toAccount: Account?

    var category: Category?

    var createdBy: User?

    var template: TransactionTemplate?

    @Relationship(deleteRule: .nullify, inverse: \SplitGroup.transaction)
    var splitGroup: SplitGroup?

    var member: Member?

    var merchant: Merchant?

    var project: Project?

    var parentTransaction: Transaction?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.parentTransaction)
    var splitChildren: [Transaction]? = []

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var reimbursementStatus: ReimbursementStatus {
        get { ReimbursementStatus(rawValue: reimbursementStatusRaw) ?? .none }
        set { reimbursementStatusRaw = newValue.rawValue }
    }

    var isReimbursable: Bool { reimbursementStatus != .none }

    var lendingDirection: LendingDirection? {
        get { lendingDirectionRaw.flatMap { LendingDirection(rawValue: $0) } }
        set { lendingDirectionRaw = newValue?.rawValue }
    }

    var lendingStatus: LendingStatus {
        get { LendingStatus(rawValue: lendingStatusRaw) ?? .none }
        set { lendingStatusRaw = newValue.rawValue }
    }

    var isLending: Bool { lendingDirection != nil }

    var isLendingPending: Bool { lendingStatus == .pending }

    var isSplitChild: Bool { parentTransaction != nil }

    var hasSplitChildren: Bool { splitChildren?.isEmpty == false }

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
        reimbursementStatus: ReimbursementStatus = .none,
        reimbursedById: UUID? = nil,
        lendingDirection: LendingDirection? = nil,
        lendingStatus: LendingStatus = .none,
        settledByLendingTransactionId: UUID? = nil,
        settledAmount: Decimal? = nil,
        tags: [String] = [],
        photoURLs: [String]? = nil,
        account: Account? = nil,
        toAccount: Account? = nil,
        category: Category? = nil,
        member: Member? = nil,
        merchant: Merchant? = nil,
        project: Project? = nil,
        isSplitParent: Bool = false,
        parentTransaction: Transaction? = nil
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
        self.reimbursementStatusRaw = reimbursementStatus.rawValue
        self.reimbursedById = reimbursedById
        self.lendingDirectionRaw = lendingDirection?.rawValue
        self.lendingStatusRaw = lendingStatus.rawValue
        self.settledByLendingTransactionId = settledByLendingTransactionId
        self.settledAmount = settledAmount
        self.tags = tags
        self.photoURLs = photoURLs
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.member = member
        self.merchant = merchant
        self.project = project
        self.isSplitParent = isSplitParent
        self.parentTransaction = parentTransaction
    }
}
