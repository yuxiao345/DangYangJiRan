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
        date: Date?,
        context: NSManagedObjectContext
    ) throws -> Transaction
    /// 原交易累计已退总额（refundAmount 字段优先，缺失则用 abs(amount)）
    func existingRefundTotal(for original: Transaction, context: NSManagedObjectContext) -> Decimal
    /// 剩余可退金额 = max(0, abs(原交易金额) - 累计已退)。累计退款校验的唯一真相来源。
    func remainingRefundable(for original: Transaction, context: NSManagedObjectContext) -> Decimal
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
    var merchantIDs: Set<UUID>?
    var projectIDs: Set<UUID>?
}
