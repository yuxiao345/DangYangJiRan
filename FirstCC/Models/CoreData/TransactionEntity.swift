import Foundation
@preconcurrency import CoreData

@objc(Transaction)
final class Transaction: NSManagedObject, @unchecked Sendable {
    // MARK: - Core Data attributes
    @NSManaged var id: UUID
    @NSManaged var typeRaw: String
    @NSManaged var amountInFen: Int64
    @NSManaged var currencyCode: String
    @NSManaged var exchangeRate: Double  // optional in model, use 0 as nil sentinel
    @NSManaged var convertedAmountInFen: Int64  // optional, 0 = nil
    @NSManaged var note: String?
    @NSManaged var date: Date
    @NSManaged var createdAt: Date
    @NSManaged var modifiedAt: Date
    @NSManaged var isReconciled: Bool
    @NSManaged var transferGroupId: UUID?
    @NSManaged var refundGroupId: UUID?
    @NSManaged var refundAmountInFen: Int64  // optional, 0 = nil
    @NSManaged var reimbursementStatusRaw: String
    @NSManaged var reimbursedById: UUID?
    @NSManaged var lendingDirectionRaw: String?
    @NSManaged var lendingStatusRaw: String
    @NSManaged var settledByLendingTransactionId: UUID?
    @NSManaged var settledAmountInFen: Int64  // optional, 0 = nil
    @NSManaged var tagsJSON: String
    @NSManaged var photoURLsJSON: String?
    @NSManaged var isSplitParent: Bool

    // MARK: - Relationships
    @NSManaged var ledger: Ledger?
    @NSManaged var account: Account?
    @NSManaged var toAccount: Account?
    @NSManaged var category: Category?
    @NSManaged var createdBy: User?
    @NSManaged var template: TransactionTemplate?
    @NSManaged var splitGroup: SplitGroup?
    @NSManaged var member: Member?
    @NSManaged var merchant: Merchant?
    @NSManaged var project: Project?
    @NSManaged var parentTransaction: Transaction?
    @NSManaged var splitChildren: Set<Transaction>?

    // MARK: - Enum bridges
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

    // MARK: - Int64 money bridges
    var amount: Decimal {
        get { Decimal(amountInFen) / 100 }
        set { amountInFen = Int64(truncating: (newValue * 100) as NSDecimalNumber) }
    }

    var exchangeRateValue: Double? {
        get { exchangeRate == 0 ? nil : exchangeRate }
        set { exchangeRate = newValue ?? 0 }
    }

    /// 以账本基准币种计价的金额（跨币种自动换算）
    var ledgerAmount: Decimal { convertedAmount ?? amount }

    /// 已结算金额按账本基准币种换算
    var settledAmountInLedgerCurrency: Decimal {
        guard let settled = settledAmount, settled != 0 else { return 0 }
        guard let rate = exchangeRateValue else { return settled }
        return settled * Decimal(rate)
    }

    var convertedAmount: Decimal? {
        get { convertedAmountInFen == 0 ? nil : Decimal(convertedAmountInFen) / 100 }
        set { convertedAmountInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    var refundAmount: Decimal? {
        get { refundAmountInFen == 0 ? nil : Decimal(refundAmountInFen) / 100 }
        set { refundAmountInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    var settledAmount: Decimal? {
        get { settledAmountInFen == 0 ? nil : Decimal(settledAmountInFen) / 100 }
        set { settledAmountInFen = newValue.map { Int64(truncating: ($0 * 100) as NSDecimalNumber) } ?? 0 }
    }

    // MARK: - JSON string bridges
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

    var photoURLs: [String]? {
        get {
            guard let json = photoURLsJSON,
                  let data = json.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
            return arr
        }
        set {
            if let val = newValue, let data = try? JSONEncoder().encode(val), let str = String(data: data, encoding: .utf8) {
                photoURLsJSON = str
            } else {
                photoURLsJSON = nil
            }
        }
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
        modifiedAt = Date.now
        date = Date.now
    }

    convenience init(
        type: TransactionType = .expense,
        amount: Decimal = 0,
        currencyCode: String = "CNY",
        exchangeRate: Double? = nil,
        convertedAmount: Decimal? = nil,
        note: String? = nil,
        date: Date = Date.now,
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
        parentTransaction: Transaction? = nil,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.typeRaw = type.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.exchangeRateValue = exchangeRate
        self.convertedAmount = convertedAmount
        self.note = note
        self.date = date
        self.isReconciled = isReconciled
        self.transferGroupId = transferGroupId
        self.refundGroupId = refundGroupId
        self.refundAmount = refundAmount
        self.reimbursementStatus = reimbursementStatus
        self.reimbursedById = reimbursedById
        self.lendingDirection = lendingDirection
        self.lendingStatus = lendingStatus
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

extension Transaction: Identifiable {}

extension Transaction {
    /// 支出聚合金额：普通支出返回 +abs(ledgerAmount)，退款（有 refundGroupId）返回 -abs(ledgerAmount)。
    /// 用于统计/报表中的支出汇总，退款显式从总额中减去。
    var netExpenseAmount: Decimal {
        refundGroupId != nil ? -abs(ledgerAmount) : abs(ledgerAmount)
    }
}
