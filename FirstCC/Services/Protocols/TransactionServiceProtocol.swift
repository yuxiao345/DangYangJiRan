import Foundation
@preconcurrency import CoreData

protocol TransactionServiceProtocol {
    func createTransaction(_ transaction: Transaction, ledger: Ledger, context: NSManagedObjectContext) throws
    func createTransfer(
        from sourceAccount: Account,
        to destAccount: Account,
        amount: Decimal,
        destAmount: Decimal?,
        date: Date,
        note: String?,
        ledger: Ledger,
        context: NSManagedObjectContext
    ) throws -> (Transaction, Transaction)
    func createRefund(
        for original: Transaction,
        amount: Decimal,
        context: NSManagedObjectContext
    ) throws -> Transaction
    func fetchTransactions(
        for ledger: Ledger,
        context: NSManagedObjectContext,
        filters: TransactionFilters?
    ) throws -> [Transaction]
    func updateTransaction(_ transaction: Transaction, context: NSManagedObjectContext) throws
    func deleteTransaction(_ transaction: Transaction, context: NSManagedObjectContext) throws
    /// 将交易的币种、汇率和折算金额应用到 model，统一处理跨币种转换（含 Swift 6.3 beta workaround）
    func applyCurrency(to transaction: Transaction, currencyCode: String, exchangeRate: Decimal?, ledgerCurrencyCode: String)

    /// 修复历史退款交易缺失的 member/merchant/project（从原交易回填），幂等
    func repairRefundMetadata(context: NSManagedObjectContext) throws
}

struct TransactionFilters {
    var dateRange: Range<Date>?
    var amountRange: ClosedRange<Decimal>?
    var type: TransactionType?
    var keyword: String?
    // 多选：同类 = OR, 跨类 = AND
    var categoryIDs: Set<UUID>?
    var memberIDs: Set<UUID>?
    var projectIDs: Set<UUID>?
}
